/*
 * Trang khách – chạy trong trình duyệt điện thoại, nói chuyện với app chủ
 * phòng qua REST + WebSocket (mục 9 của đặc tả).
 *
 * Nguyên tắc: không bao giờ dùng innerHTML cho dữ liệu từ YouTube. Mọi tiêu
 * đề / tên kênh đều gán bằng textContent để tự động escape.
 */
(function () {
  'use strict';

  var $ = function (id) { return document.getElementById(id); };

  // ------------------------------------------------------------ danh tính

  var ROOM = new URLSearchParams(location.search).get('room') || '';
  var LS_ID = 'kara.guestId';
  var LS_NAME = 'kara.guestName';
  var LS_KARAOKE = 'kara.preferKaraoke';

  function uuid() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    return 'g-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 10);
  }

  var guestId = localStorage.getItem(LS_ID);
  if (!guestId) { guestId = uuid(); localStorage.setItem(LS_ID, guestId); }
  var guestName = localStorage.getItem(LS_NAME) || '';

  // ------------------------------------------------------------ tiện ích

  function show(el, visible) { el.hidden = !visible; }

  function clear(el) { while (el.firstChild) el.removeChild(el.firstChild); }

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = text;
    return node;
  }

  var toastTimer = null;
  function toast(message, isError) {
    var box = $('toast');
    box.textContent = message;
    box.className = 'toast' + (isError ? ' error' : '');
    show(box, true);
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { show(box, false); }, 3200);
  }

  function api(path, options) {
    return fetch(path, options).then(function (res) {
      return res.json().catch(function () { return {}; }).then(function (body) {
        if (!res.ok) throw new Error(body.error || 'Lỗi ' + res.status);
        return body;
      });
    });
  }

  function post(path, payload) {
    payload.room = ROOM;
    payload.guestId = guestId;
    payload.name = guestName;
    return api(path, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload)
    });
  }

  // ----------------------------------------------------------- cổng vào tên

  function openGate() {
    show($('gate'), true);
    $('gate-name').value = guestName;
    $('gate-name').focus();
  }

  function submitGate() {
    var name = $('gate-name').value.trim();
    if (name.length < 1) {
      $('gate-error').textContent = 'Nhập tên giúp mình nhé.';
      show($('gate-error'), true);
      return;
    }
    guestName = name;
    localStorage.setItem(LS_NAME, name);
    show($('gate'), false);
    connect();
  }

  $('gate-go').addEventListener('click', submitGate);
  $('gate-name').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') submitGate();
  });

  // ------------------------------------------------------------------- tab

  var tabs = ['search', 'mine', 'queue'];
  Array.prototype.forEach.call(document.querySelectorAll('.tabbtn'), function (btn) {
    btn.addEventListener('click', function () {
      var name = btn.getAttribute('data-tab');
      tabs.forEach(function (t) { show($('tab-' + t), t === name); });
      Array.prototype.forEach.call(document.querySelectorAll('.tabbtn'), function (b) {
        b.classList.toggle('active', b === btn);
      });
      window.scrollTo(0, 0);
    });
  });

  // -------------------------------------------------------------- WebSocket

  var ws = null;
  var reconnectDelay = 1000;
  var lastState = null;

  function setConn(status) {
    $('conn').className = 'conn ' + status;
  }

  function connect() {
    if (ws && (ws.readyState === 0 || ws.readyState === 1)) return;

    var proto = location.protocol === 'https:' ? 'wss://' : 'ws://';
    try {
      ws = new WebSocket(proto + location.host + '/ws');
    } catch (e) {
      scheduleReconnect();
      return;
    }

    ws.onopen = function () {
      setConn('online');
      reconnectDelay = 1000;
      ws.send(JSON.stringify({ type: 'hello', guestId: guestId, name: guestName }));
    };

    ws.onmessage = function (event) {
      var msg;
      try { msg = JSON.parse(event.data); } catch (e) { return; }
      switch (msg.type) {
        case 'state': applyState(msg); break;
        case 'request_update': renderMine(msg.mine || []); break;
        case 'progress': applyProgress(msg); break;
        case 'toast': toast(msg.message, msg.isError); break;
      }
    };

    ws.onclose = function () { setConn('offline'); scheduleReconnect(); };
    ws.onerror = function () { setConn('offline'); };
  }

  function scheduleReconnect() {
    setTimeout(connect, reconnectDelay);
    reconnectDelay = Math.min(reconnectDelay * 2, 15000);
    if (reconnectDelay >= 15000) {
      toast('Mất kết nối với phòng. Hãy quét lại mã QR.', true);
    }
  }

  // Giữ kết nối sống khi màn hình điện thoại vừa bật lại.
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden) connect();
  });
  setInterval(function () {
    if (ws && ws.readyState === 1) ws.send(JSON.stringify({ type: 'ping' }));
  }, 25000);

  // ------------------------------------------------------- hiển thị trạng thái

  /**
   * Chủ phòng kết thúc buổi hát thì mã phòng được sinh lại, nên mã trong URL
   * của khách thành vô hiệu. Nói thẳng ra thay vì để khách gửi bài rồi nhận
   * lỗi 403 không hiểu vì sao.
   */
  function roomStillValid(state) {
    if (!ROOM || !state.roomCode) return true;
    var valid = state.roomCode === ROOM;
    show($('expired'), !valid);
    return valid;
  }

  $('expired-retry').addEventListener('click', function () {
    location.reload();
  });

  function applyState(state) {
    lastState = state;
    if (!roomStillValid(state)) return;

    var current = state.current;
    $('now-title').textContent = current
      ? current.song.title + ' – ' + current.requestedBy.name
      : 'Chưa có bài nào';

    var upnext = $('upnext');
    if (state.upNext) {
      clear(upnext);
      upnext.appendChild(document.createTextNode('Tiếp theo: '));
      upnext.appendChild(el('b', null,
        state.upNext.requestedBy.name + ' – ' + state.upNext.song.title));
      show(upnext, true);
    } else {
      show(upnext, false);
    }

    applyProgress(state.tv || {});
    renderQueue(state.queue || []);
    if (state.mine) renderMine(state.mine);
  }

  function applyProgress(p) {
    var duration = p.duration || 0;
    var position = p.position || 0;
    var pct = duration > 0 ? Math.min(100, (position / duration) * 100) : 0;
    $('progress-fill').style.width = pct + '%';
  }

  // --------------------------------------------------------------- thẻ bài

  function fmtDuration(seconds) {
    if (!seconds || seconds <= 0) return '--:--';
    var h = Math.floor(seconds / 3600);
    var m = Math.floor((seconds % 3600) / 60);
    var s = Math.floor(seconds % 60);
    var pad = function (n) { return n < 10 ? '0' + n : '' + n; };
    return h > 0 ? h + ':' + pad(m) + ':' + pad(s) : m + ':' + pad(s);
  }

  /**
   * Thẻ hiển thị một bài. `options.actions` là mảng {label, className, onClick}.
   */
  function songCard(song, metaLine, options) {
    options = options || {};
    var card = el('div', 'card');

    var thumb = el('div', 'thumb');
    var img = document.createElement('img');
    img.loading = 'lazy';
    img.src = song.thumbUrl;
    img.alt = '';
    thumb.appendChild(img);
    thumb.appendChild(el('span', 'dur', song.durationText || fmtDuration(song.durationSec)));
    if (options.preview !== false) {
      thumb.addEventListener('click', function () { openPreview(song); });
    }
    card.appendChild(thumb);

    var body = el('div', 'card-body');
    body.appendChild(el('p', 'card-title', song.title));
    body.appendChild(el('div', 'card-meta', metaLine));

    var actions = el('div', 'card-actions');
    (options.tags || []).forEach(function (tag) {
      actions.appendChild(el('span', 'tag ' + (tag.kind || ''), tag.label));
    });
    (options.actions || []).forEach(function (action) {
      var btn = el('button', 'btn ' + (action.className || 'btn-request'), action.label);
      btn.addEventListener('click', function () { action.onClick(btn); });
      actions.appendChild(btn);
    });
    if (actions.childNodes.length) body.appendChild(actions);

    card.appendChild(body);
    return card;
  }

  function metaOf(song) {
    var bits = [song.channel];
    if (song.viewCountText) bits.push(song.viewCountText);
    if (song.publishedText) bits.push(song.publishedText);
    return bits.filter(Boolean).join(' • ');
  }

  // -------------------------------------------------------------- tìm bài

  var searchState = { query: '', page: 0, loading: false, done: false };

  var suggestTimer = null;
  var qInput = $('q');

  $('prefer-karaoke').checked = localStorage.getItem(LS_KARAOKE) !== '0';
  $('prefer-karaoke').addEventListener('change', function () {
    localStorage.setItem(LS_KARAOKE, this.checked ? '1' : '0');
    if (searchState.query) runSearch(searchState.query, true);
  });

  qInput.addEventListener('input', function () {
    show($('q-clear'), qInput.value.length > 0);
    clearTimeout(suggestTimer);
    var q = qInput.value.trim();
    if (q.length < 2 || /youtu/.test(q)) { show($('suggests'), false); return; }
    // Gợi ý khi gõ, debounce 250 ms (mục 6).
    suggestTimer = setTimeout(function () { loadSuggests(q); }, 250);
  });

  qInput.addEventListener('keydown', function (e) {
    if (e.key === 'Enter') {
      e.preventDefault();
      qInput.blur();
      show($('suggests'), false);
      runSearch(qInput.value, true);
    }
  });

  $('q-clear').addEventListener('click', function () {
    qInput.value = '';
    show($('q-clear'), false);
    show($('suggests'), false);
    clear($('results'));
    show($('search-status'), false);
    searchState = { query: '', page: 0, loading: false, done: false };
  });

  function loadSuggests(q) {
    api('/api/suggest?q=' + encodeURIComponent(q)).then(function (body) {
      var list = $('suggests');
      clear(list);
      (body.suggestions || []).slice(0, 8).forEach(function (s) {
        var li = el('li', null, s);
        li.addEventListener('click', function () {
          qInput.value = s;
          show(list, false);
          runSearch(s, true);
        });
        list.appendChild(li);
      });
      show(list, list.childNodes.length > 0);
    }).catch(function () { show($('suggests'), false); });
  }

  function setSearchStatus(text, isError) {
    var box = $('search-status');
    box.textContent = text || '';
    box.className = 'status' + (isError ? ' error' : '');
    show(box, !!text);
  }

  function runSearch(rawQuery, reset) {
    var q = (rawQuery || '').trim();
    if (!q) return;

    if (reset) {
      searchState = { query: q, page: 0, loading: false, done: false };
      clear($('results'));
      setSearchStatus('Đang tìm…');
    }
    if (searchState.loading || searchState.done) return;

    searchState.loading = true;
    show($('results-more'), searchState.page > 0);

    var karaoke = $('prefer-karaoke').checked ? '1' : '0';
    var url = '/api/search?q=' + encodeURIComponent(searchState.query) +
      '&page=' + searchState.page + '&karaoke=' + karaoke;

    api(url).then(function (body) {
      searchState.loading = false;
      show($('results-more'), false);
      var results = body.results || [];
      if (results.length === 0) {
        searchState.done = true;
        if (searchState.page === 0) setSearchStatus('Không tìm thấy bài nào.');
        return;
      }
      setSearchStatus('');
      searchState.page += 1;
      results.forEach(function (song) { $('results').appendChild(resultCard(song)); });
    }).catch(function (err) {
      searchState.loading = false;
      show($('results-more'), false);
      setSearchStatus(
        navigator.onLine ? (err.message || 'Không tìm được.') : 'Không có Internet',
        true
      );
    });
  }

  function resultCard(song) {
    var tags = [];
    if (song.inQueue) tags.push({ label: 'Đã có trong hàng chờ', kind: 'ok' });
    if (song.embeddable === false) {
      tags.push({ label: 'Có thể không phát được', kind: 'warn' });
    }

    return songCard(song, metaOf(song), {
      tags: tags,
      actions: [{
        label: 'Yêu cầu bài này',
        className: 'btn-primary btn-request',
        onClick: function (btn) { requestSong(song, btn); }
      }]
    });
  }

  function requestSong(song, btn) {
    btn.disabled = true;
    btn.textContent = 'Đang gửi…';
    post('/api/request', { song: song }).then(function (body) {
      var queued = body.item && body.item.status === 'queued';
      btn.textContent = queued ? 'Đã vào hàng chờ' : 'Đã gửi yêu cầu';
    }).catch(function (err) {
      btn.disabled = false;
      btn.textContent = 'Yêu cầu bài này';
      toast(err.message || 'Không gửi được yêu cầu', true);
    });
  }

  // Cuộn vô hạn: tải trang kế tiếp khi gần cuối trang.
  window.addEventListener('scroll', function () {
    if ($('tab-search').hidden) return;
    var nearBottom = window.innerHeight + window.scrollY >=
      document.body.offsetHeight - 600;
    if (nearBottom) runSearch(searchState.query, false);
  }, { passive: true });

  // ---------------------------------------------------------- bài của tôi

  function statusTag(item) {
    switch (item.status) {
      case 'pending': return { label: 'Chờ duyệt', kind: 'warn' };
      case 'queued':
        return {
          label: item.position ? 'Trong hàng chờ (vị trí ' + item.position + ')' : 'Trong hàng chờ',
          kind: ''
        };
      case 'playing': return { label: 'Đang hát', kind: 'accent' };
      case 'played': return { label: 'Đã hát', kind: 'ok' };
      case 'rejected': return { label: 'Bị từ chối', kind: 'warn' };
      case 'skipped': return { label: item.note || 'Đã bỏ qua', kind: 'warn' };
      case 'cancelled': return { label: 'Đã huỷ', kind: '' };
      default: return { label: item.status, kind: '' };
    }
  }

  function renderMine(items) {
    var box = $('mine');
    clear(box);

    var active = items.filter(function (i) {
      return i.status === 'pending' || i.status === 'queued' || i.status === 'playing';
    }).length;
    var badge = $('mine-badge');
    badge.textContent = active;
    show(badge, active > 0);

    show($('mine-empty'), items.length === 0);

    items.forEach(function (item) {
      var actions = [];
      if (item.status === 'pending') {
        actions.push({
          label: 'Huỷ yêu cầu',
          className: 'btn-request',
          onClick: function (btn) {
            btn.disabled = true;
            post('/api/request/cancel', { uid: item.uid }).catch(function (err) {
              btn.disabled = false;
              toast(err.message || 'Không huỷ được', true);
            });
          }
        });
      }
      if (item.status === 'played' || item.status === 'rejected' ||
          item.status === 'cancelled' || item.status === 'skipped') {
        actions.push({
          label: 'Yêu cầu lại',
          className: 'btn-primary btn-request',
          onClick: function (btn) { requestSong(item.song, btn); }
        });
      }
      box.appendChild(songCard(item.song, metaOf(item.song), {
        tags: [statusTag(item)],
        actions: actions
      }));
    });
  }

  // -------------------------------------------------------------- hàng chờ

  function renderQueue(queue) {
    var box = $('queue');
    clear(box);
    show($('queue-empty'), queue.length === 0);

    var badge = $('queue-badge');
    badge.textContent = queue.length;
    show(badge, queue.length > 0);

    queue.forEach(function (item, index) {
      box.appendChild(songCard(item.song, metaOf(item.song), {
        tags: [
          { label: '#' + (index + 1), kind: '' },
          { label: item.requestedBy.name, kind: 'ok' }
        ],
        preview: false
      }));
    });
  }

  // ------------------------------------------------------- xem trước 15 giây

  var previewTimer = null;

  function openPreview(song) {
    clearTimeout(previewTimer);
    $('preview-title').textContent = song.title;
    var frame = $('preview-frame');
    clear(frame);

    var iframe = document.createElement('iframe');
    iframe.allow = 'autoplay; encrypted-media';
    iframe.allowFullscreen = false;
    iframe.src = 'https://www.youtube.com/embed/' + encodeURIComponent(song.videoId) +
      '?autoplay=1&rel=0&modestbranding=1&playsinline=1';
    frame.appendChild(iframe);
    show($('preview'), true);

    previewTimer = setTimeout(closePreview, 15000);
  }

  function closePreview() {
    clearTimeout(previewTimer);
    clear($('preview-frame'));
    show($('preview'), false);
  }

  $('preview-close').addEventListener('click', closePreview);
  $('preview').addEventListener('click', function (e) {
    if (e.target === $('preview')) closePreview();
  });

  // ------------------------------------------------------------- khởi động

  api('/api/state?guestId=' + encodeURIComponent(guestId) +
      '&name=' + encodeURIComponent(guestName || 'Khách'))
    .then(applyState)
    .catch(function () { setConn('offline'); });

  if (guestName) {
    connect();
  } else {
    openGate();
  }
})();
