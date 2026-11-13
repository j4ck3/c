/**
 * Slate: preload message previews so a click shows the message at once.
 *
 * Roundcube shows a message by loading `?_action=preview` into the content iframe.
 * That request has to sign in to Outlook (about a second) before it can render.
 * This module loads likely-next previews into hidden iframes ahead of time and,
 * when the user opens one of them, swaps the ready frame in for the visible one.
 *
 * What gets preloaded (at most MAX_FRAMES frames, MAX_PARALLEL loading at once):
 * - the first FIRST_ROWS rows after the list loads,
 * - then unread rows in list order, up to LIST_BUDGET preloads from the list load,
 * - the row under the pointer after HOVER_DELAY ms,
 * - the next and previous row around the message being read.
 * The slots between LIST_BUDGET and MAX_FRAMES stay free for hover and neighbours.
 *
 * Prefetch requests carry `_prefetch=1`. The slate_prefetch plugin then keeps the
 * preview free of side effects: no read flag, no read receipt, no remote images.
 * When a preloaded message is shown, this module marks it as read with the
 * normal `mark` request. Preloads expire after TTL_MS and are dropped whenever
 * the list changes (folder switch, refresh, search, move, delete).
 */
(function ($) {
    'use strict';

    var rcmail = window.rcmail;

    if (!rcmail || rcmail.env.task != 'mail' || rcmail.env.action || !rcmail.env.contentframe) {
        return;
    }

    var MAX_FRAMES = 12,
        LIST_BUDGET = 8,
        MAX_PARALLEL = 3,
        FIRST_ROWS = 3,
        HOVER_DELAY = 150,
        TTL_MS = 30 * 60 * 1000,
        stats = [], // last open timings, see window.slatePrefetch.stats()
        cache = {}, // key -> { frame, uid, mbox, url, ready, failed, time, onready }
        order = [], // keys, oldest first
        loading = 0,
        queue = [],
        hover_timer,
        generation = 0;

    function list() {
        return rcmail.message_list;
    }

    function wrapper() {
        return $('#' + rcmail.env.contentframe).parent();
    }

    function key(uid) {
        return rcmail.get_message_mailbox(uid) + '/' + uid;
    }

    function preview_url(uid, prefetch) {
        var params = rcmail.params_from_uid(uid, { _caps: rcmail.browser_capabilities(), _framed: 1 });

        if (rcmail.env.search_request) {
            params._search = rcmail.env.search_request;
        }

        if (prefetch) {
            params._prefetch = 1;
        }

        return rcmail.url('preview', params);
    }

    function is_draft(uid) {
        return rcmail.get_message_mailbox(uid) == rcmail.env.drafts_mailbox;
    }

    function drop(k) {
        var entry = cache[k];

        if (entry) {
            if (!entry.ready && !entry.failed) {
                loading = Math.max(0, loading - 1);
            }
            entry.frame.remove();
            delete cache[k];
        }

        order = order.filter(function (o) {
            return o != k;
        });
    }

    function drop_all() {
        generation++;
        queue = [];
        Object.keys(cache).forEach(drop);
    }

    function expire() {
        var now = Date.now();

        Object.keys(cache).forEach(function (k) {
            if (now - cache[k].time > TTL_MS) {
                drop(k);
            }
        });
    }

    // drop preloads whose row is no longer in the list
    function prune_missing() {
        var l = list();

        Object.keys(cache).forEach(function (k) {
            if (!l || !l.rows[cache[k].uid]) {
                drop(k);
            }
        });
    }

    function pump() {
        while (loading < MAX_PARALLEL && queue.length) {
            start(queue.shift());
        }
    }

    function start(uid) {
        var k = key(uid);

        if (cache[k] || !list() || !list().rows[uid]) {
            return;
        }

        // keep the pool small: drop the oldest finished preload
        while (order.length >= MAX_FRAMES) {
            drop(order[0]);
        }

        var gen = generation,
            frame = $('<iframe class="slate-prefetch-frame" tabindex="-1" aria-hidden="true">')
                .attr({ name: 'slate-prefetch-' + k.replace(/[^\w-]/g, '_'), title: '' }),
            entry = {
                frame: frame,
                uid: uid,
                mbox: rcmail.get_message_mailbox(uid),
                ready: false,
                failed: false,
                time: Date.now(),
            };

        cache[k] = entry;
        order.push(k);
        loading++;

        frame.on('load', function () {
            if (gen != generation || cache[k] !== entry || entry.ready) {
                return;
            }

            var win, env;

            try {
                win = frame[0].contentWindow;
                env = win.rcmail && win.rcmail.env;
            } catch (e) { /* ignore */ }

            loading = Math.max(0, loading - 1);

            // Only keep frames that rendered a prefetched preview. Anything else
            // (error page, session expiry, read-receipt request) loads normally on click.
            if (env && env.slate_prefetched && env.uid && !env.mdn_request) {
                entry.ready = true;
                entry.time = Date.now();
                if (entry.onready) {
                    entry.onready();
                }
            } else {
                entry.failed = true;
                drop(k);
            }

            pump();
        });

        frame.attr('src', preview_url(uid, true)).appendTo(wrapper());
    }

    function prefetch(uid) {
        if (!uid || is_draft(uid) || cache[key(uid)] || queue.indexOf(uid) >= 0) {
            return;
        }

        queue.push(uid);
        pump();
    }

    function prefetch_first_rows() {
        var l = list(), uid, n = 0, row, first = 0;

        if (!l || !l.rowcount) {
            return;
        }

        row = l.rows[l.get_first_row()];
        while (row && n < LIST_BUDGET) {
            uid = row.uid;
            // the first rows always, after that only unread messages
            if (first < FIRST_ROWS || row.unread) {
                if (!cache[key(uid)]) {
                    prefetch(uid);
                }
                n++;
            }
            first++;
            row = l.rows[l.get_row_uid(l.get_next_row(uid))];
        }
    }

    function prefetch_neighbours(uid) {
        var l = list(), next, prev;

        if (!l || !uid) {
            return;
        }

        next = l.get_next_row(uid);
        prev = l.get_prev_row(uid);

        if (next) {
            prefetch(l.get_row_uid(next));
        }

        if (prev) {
            prefetch(l.get_row_uid(prev));
        }
    }

    /**
     * Swap a ready prefetch frame in as the content frame.
     */
    function show_prefetched(entry) {
        var current = $('#' + rcmail.env.contentframe),
            frame = entry.frame,
            id = current.attr('id'),
            name = current.attr('name'),
            attrs = {
                id: id,
                name: name,
                title: current.attr('title'),
                'aria-labelledby': current.attr('aria-labelledby'),
            },
            win = frame[0].contentWindow,
            uid = entry.uid,
            mbox = entry.mbox,
            unread = list().rows[uid] && list().rows[uid].unread;

        // The ready frame takes over the content frame's identity; the old one is removed.
        delete cache[key(uid)];
        order = order.filter(function (o) {
            return o != key(uid);
        });

        current.removeAttr('id').attr('name', '');
        frame.removeClass('slate-prefetch-frame').removeAttr('aria-hidden tabindex').attr(attrs);
        current.remove();

        // Roundcube looks frames up via window.frames[name]; the name changed above.
        try {
            win.name = name;
        } catch (e) { /* ignore */ }

        rcmail.preview_id = uid;
        rcmail.show_contentframe(true);
        frame.show();

        // ui.js runs its layout logic (title, phone view) on the content frame's load event.
        // The frame is already loaded, so hook it up and run the handler once now.
        if (window.UI && UI.bind_content_frame) {
            UI.bind_content_frame(frame);
        }
        frame.trigger('load');

        // The preview frame enables its own commands on init; ask it to talk to us again.
        try {
            if (win.rcmail) {
                win.rcmail.enable_command(win.rcmail.env.message_commands, win.rcmail.env.uid);
            }
        } catch (e) { /* ignore */ }

        // The list page has no mail_read_time in env; the plugin sends the user's value
        // as slate_mail_read_time. 0 = mark at once (Roundcube default).
        var read_time = parseInt(rcmail.env.slate_mail_read_time || 0, 10);

        if (unread && read_time > 0) {
            setTimeout(function () {
                if (rcmail.preview_id == uid) {
                    rcmail.http_post('mark', { _uid: uid, _flag: 'read', _mbox: mbox, _quiet: 1 });
                    rcmail.set_unread_message(uid, mbox);
                }
            }, read_time * 1000);
        } else if (unread && read_time == 0) {
            rcmail.http_post('mark', { _uid: uid, _flag: 'read', _mbox: mbox, _quiet: 1 });
            rcmail.set_unread_message(uid, mbox);
        }

        rcmail.triggerEvent('slate-prefetch-hit', { uid: uid });

        return true;
    }

    // Intercept Roundcube's preview loader.
    var orig_get_preview = rcmail.msglist_get_preview;

    function record(uid, type, t0) {
        stats.push({ uid: uid, type: type, ms: Math.round(performance.now() - t0) });
        if (stats.length > 50) {
            stats.shift();
        }
    }

    rcmail.msglist_get_preview = function () {
        var uid = this.get_single_uid(),
            entry = uid && cache[key(uid)],
            t0 = performance.now();

        if (entry && entry.ready && Date.now() - entry.time <= TTL_MS && !this.drag_active) {
            show_prefetched(entry);
            // time until the swapped frame has been painted
            requestAnimationFrame(function () {
                record(uid, 'hit', t0);
            });
            prefetch_neighbours(uid);
            return;
        }

        // still loading: show it as soon as it is ready, unless the user moves on
        if (entry && !entry.ready && !entry.failed) {
            var self = this;
            entry.onready = function () {
                if (self.get_single_uid() == uid) {
                    show_prefetched(entry);
                    record(uid, 'waited', t0);
                    prefetch_neighbours(uid);
                }
            };
            this.show_contentframe(false);
            return;
        }

        orig_get_preview.apply(this, arguments);
        if (uid) {
            $('#' + rcmail.env.contentframe).one('load', function () {
                record(uid, 'miss', t0);
            });
        }
        prefetch_neighbours(uid);
    };

    // Anything that changes the list or the messages invalidates the preloads.
    rcmail.addEventListener('beforelist', drop_all)
        .addEventListener('beforesearch', drop_all)
        .addEventListener('beforemove', drop_all)
        .addEventListener('beforedelete', drop_all)
        .addEventListener('beforeplugin.archive', drop_all)
        .addEventListener('beforeplugin.markasjunk.junk', drop_all)
        .addEventListener('beforeplugin.markasjunk.not_junk', drop_all)
        .addEventListener('beforecheckmail', drop_all)
        .addEventListener('listupdate', function () {
            expire();
            prune_missing();
            setTimeout(prefetch_first_rows, 300);
        })
        // the minute refresh removes rows moved or deleted elsewhere (phone, Outlook)
        .addEventListener('responseafterrefresh', prune_missing)
        .addEventListener('responseaftercheck-recent', prune_missing);

    rcmail.addEventListener('init', function () {
        var l = list();

        if (!l) {
            return;
        }

        // hover prefetch (pointer devices only)
        $(l.list).on('mouseenter', 'tr', function () {
            var uid = this.uid;
            clearTimeout(hover_timer);
            if (uid) {
                hover_timer = setTimeout(function () {
                    prefetch(uid);
                }, HOVER_DELAY);
            }
        }).on('mouseleave', 'tr', function () {
            clearTimeout(hover_timer);
        });

        // touch: start loading as soon as the finger lands on a row
        $(l.list).on('touchstart', 'tr', function () {
            prefetch(this.uid);
        });
    });

    // for diagnostics in the browser console
    window.slatePrefetch = {
        cache: function () {
            return Object.keys(cache).map(function (k) {
                return { key: k, ready: cache[k].ready, age: Math.round((Date.now() - cache[k].time) / 1000) };
            });
        },
        clear: drop_all,
        // open timings: hit = preloaded, waited = preload still loading, miss = normal load
        stats: function () {
            var sum = {};
            stats.forEach(function (s) {
                var t = sum[s.type] || (sum[s.type] = { count: 0, total: 0, max: 0 });
                t.count++;
                t.total += s.ms;
                t.max = Math.max(t.max, s.ms);
            });
            Object.keys(sum).forEach(function (k) {
                sum[k].avg = Math.round(sum[k].total / sum[k].count);
                delete sum[k].total;
            });
            return { summary: sum, last: stats.slice(-10) };
        },
    };
})(jQuery);
