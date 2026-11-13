/**
 * Slate skin behaviour that Elastic's ui.js does not provide.
 *
 * - one-line message rows (sender, subject, date)
 * - unread/flagged filter pills above the message list
 * - folder sidebar shows the main folders, the rest behind a toggle
 * - plugin toolbar buttons (archive, junk) move into the "more" menu
 * - right-click on a message opens the "more" menu
 * - phone bottom navigation (Inbox, Junk, Settings) with unread badges
 *
 * Loaded after ui.js (see templates/includes/footer.html).
 */
(function ($) {
    if (!window.rcmail || !window.UI) {
        return;
    }

    var rcmail = window.rcmail;

    /**
     * Message rows: one line with sender, subject and date.
     * Elastic's widescreen template stacks sender/date over the subject.
     */
    function setup_message_rows() {
        if (rcmail.env.task != 'mail' || !rcmail.gui_objects.messagelist) {
            return;
        }

        rcmail.env.widescreen_list_template = [
            { className: 'threads', cells: ['threads'] },
            { className: 'subject', cells: ['fromto', 'subject', 'flag', 'attachment', 'size', 'date'] },
        ];

        $(rcmail.gui_objects.messagelist).addClass('slate-oneline');

        var now = new Date(),
            months = (rcmail.get_label('slate_months') || '').split(','),
            button = function (action, label) {
                return $('<a href="#" role="button" tabindex="-1">')
                    .attr({ 'data-action': action, title: rcmail.get_label(label) })
                    .addClass('slate-row-action ' + action);
            },
            actions = $('<span class="slate-row-actions skip-on-drag">').append(
                button('delete', 'delete'),
                button('move', 'moveto'),
                button('unread', 'markasunread'),
                button('read', 'markasread')
            );

        // Buttons sit inside the row. list.js binds mousedown/mouseup on each <tr>, so stop
        // those events in the capture phase on the table, before they reach the row.
        $.each(['mousedown', 'mouseup', 'touchstart', 'touchend', 'dblclick'], function (i, type) {
            rcmail.gui_objects.messagelist.addEventListener(type, function (e) {
                if ($(e.target).closest('a.slate-row-action').length) {
                    e.stopPropagation();
                }
            }, true);
        });

        $(rcmail.gui_objects.messagelist)
            .on('click', 'a.slate-row-action', function (e) {
                var uid = $(this).closest('tr')[0].uid;

                e.preventDefault();
                e.stopPropagation();

                if (!uid) {
                    return false;
                }

                switch ($(this).data('action')) {
                    case 'delete':
                        rcmail.delete_messages(e, uid);
                        break;
                    case 'move':
                        rcmail.folder_selector(e, function (folder) {
                            rcmail.move_messages(folder, e, [uid]);
                        });
                        break;
                    case 'unread':
                        rcmail.mark_message('unread', uid);
                        break;
                    case 'read':
                        rcmail.mark_message('read', uid);
                        break;
                }

                return false;
            });

        rcmail.addEventListener('insertrow', function (p) {
            var row = p.row && p.row.obj ? $(p.row.obj) : $(),
                cell = row.children('td.subject'),
                date = cell.children('span.date'),
                text = date.text(),
                m;

            if (!cell.length) {
                return;
            }

            // status dot first, before the sender
            cell.find('span.subject > span.msgicon').prependTo(cell);

            // hover actions; they replace the date while the pointer is over the row
            cell.append(actions.clone());

            // compact date: time for today, "21 sep" this year, otherwise yyyy-mm-dd
            if ((m = /^(\d{4})-(\d{2})-(\d{2}) (\d{2}:\d{2})$/.exec(text))) {
                date.attr('title', text);
                if (+m[1] == now.getFullYear() && +m[2] == now.getMonth() + 1 && +m[3] == now.getDate()) {
                    date.text(m[4]);
                } else if (+m[1] == now.getFullYear() && months.length == 12) {
                    date.text(+m[3] + ' ' + months[+m[2] - 1]);
                } else {
                    date.text(m[1] + '-' + m[2] + '-' + m[3]);
                }
            } else if ((m = /^\S+ (\d{2}:\d{2})$/.exec(text))) {
                // "Today 10:45" / "Mon 10:45" from Roundcube's pretty dates
                date.attr('title', text);
                if (/^(idag|today)/i.test(text)) {
                    date.text(m[1]);
                }
            }
        });
    }

    /**
     * Filter pills (All / Unread / Flagged) mirror the hidden search filter select.
     */
    function setup_filters() {
        var pills = $('.slate-filters .slate-filter'),
            select = function () {
                return $(rcmail.gui_objects.search_filter);
            },
            sync = function () {
                var value = select().val() || 'ALL';
                pills.each(function () {
                    $(this).toggleClass('selected', $(this).data('filter') == value);
                });
            };

        if (!pills.length) {
            return;
        }

        pills.on('click', function (e) {
            e.preventDefault();
            var value = $(this).data('filter');
            if (!select().length) {
                return;
            }
            select().val(value);
            rcmail.command('search');
            sync();
        });

        rcmail.addEventListener('listupdate', sync);
        sync();
    }

    /**
     * Sidebar: show the main folders; others collapse behind a toggle link.
     */
    function setup_folders() {
        var list = $('#mailboxlist'),
            toggle = $('#slate-more-folders'),
            env = rcmail.env,
            main = [],
            extra;

        if (!list.length) {
            return;
        }

        // Inbox, Drafts, Sent, Archive, Junk, Trash - in this order
        $.each([
            list.children('li.inbox'),
            list.children('li.drafts'),
            list.children('li.sent'),
            env.archive_folder ? $(rcmail.get_folder_li(env.archive_folder, '', true)) : $(),
            list.children('li.junk'),
            list.children('li.trash'),
        ], function (i, li) {
            if (li && li.length && li.parent().is(list) && main.indexOf(li[0]) < 0) {
                main.push(li[0]);
                li.appendTo(list);
            }
        });

        extra = list.children('li').filter(function () {
            return main.indexOf(this) < 0;
        });

        // keep the currently open folder visible
        extra.not('.selected').filter(function () {
            return !$(this).find('.selected').length;
        }).addClass('slate-extra-folder');

        extra.appendTo(list);

        if (!list.children('li.slate-extra-folder').length) {
            return;
        }

        toggle.removeClass('hidden').on('click', function (e) {
            e.preventDefault();
            var open = !list.is('.slate-show-all');
            list.toggleClass('slate-show-all', open);
            toggle.toggleClass('open', open).attr('aria-expanded', open ? 'true' : 'false');
        });
    }

    /**
     * Move plugin toolbar buttons (archive, junk, not junk) into the more menu.
     */
    function setup_plugin_buttons() {
        var holder = $('#slate-plugin-toolbar'),
            menu = $('#message-menu > ul');

        if (!menu.length) {
            return;
        }

        // markasjunk in menu mode puts its items into the markmenu container, which is at the end
        holder.children('a').get().reverse().forEach(function (button) {
            var a = $(button),
                li = $('<li role="menuitem">');

            a.removeClass('button').attr('role', 'menuitem');
            a.find('span.inner').removeClass('inner');
            li.append(a).prependTo(menu);
        });

        // order: Forward, Archive, Junk / Not junk, then the rest
        var archive = menu.children('li').has('a.archive');
        menu.children('li').has('a.junk, a.notjunk').get().reverse().forEach(function (li) {
            if (archive.length) {
                $(li).insertAfter(archive);
            } else {
                $(li).prependTo(menu);
            }
        });
        menu.children('li').has('a.forward:not(.more)').first().prependTo(menu);
        holder.remove();
        rcmail.markasjunk_toggle_button && rcmail.markasjunk_toggle_button();
    }

    /**
     * Right-click on a message row opens the more menu at the pointer.
     */
    function setup_context_menu() {
        var list = rcmail.message_list;

        if (!list || UI.is_touch()) {
            return;
        }

        $(list.list).on('contextmenu', 'tr', function (e) {
            var uid = this.uid,
                button = $('#messagemenulink'),
                anchor;

            if (!uid || !button.length || e.shiftKey) {
                return;
            }

            e.preventDefault();

            if (!list.in_selection(uid)) {
                list.select(uid);
            }

            // anchor the popover at the pointer
            anchor = $('#slate-context-anchor');
            if (!anchor.length) {
                anchor = $('<a id="slate-context-anchor" href="#" tabindex="-1" aria-hidden="true">')
                    .attr('data-popup', 'message-menu')
                    .appendTo(document.body);
                UI.popup_init(anchor[0]);
            }

            anchor.css({
                position: 'absolute', display: 'block', width: '1px', height: '1px', left: e.pageX + 'px', top: e.pageY + 'px',
            }).data('popup-pos', 'bottom');

            setTimeout(function () {
                anchor.popover('show');
            }, 10);
        });
    }

    /**
     * Phone bottom navigation: mark the active tab and show unread badges.
     */
    function setup_bottomnav() {
        var nav = $('#slate-bottomnav'),
            env = rcmail.env;

        if (!nav.length) {
            return;
        }

        $('body').addClass('slate-has-bottomnav');

        // env.junk_mailbox only exists in the mail task; remember it for the other pages
        if (env.junk_mailbox) {
            rcmail.local_storage_set_item('slate.junk', env.junk_mailbox);
        }

        var junk = env.junk_mailbox || rcmail.local_storage_get_item('slate.junk') || 'Junk',
            link = function (query) {
                return './?' + $.param(query);
            },
            tabs = {
                inbox: nav.find('a.tab-inbox'),
                junk: nav.find('a.tab-junk'),
                settings: nav.find('a.tab-settings'),
            },
            update = function () {
                var mbox = env.mailbox,
                    counts = env.unread_counts || {};

                nav.find('a').removeClass('selected').removeAttr('aria-current');

                if (rcmail.task == 'settings') {
                    tabs.settings.addClass('selected');
                } else if (rcmail.task == 'mail' && mbox == junk) {
                    tabs.junk.addClass('selected');
                } else if (rcmail.task == 'mail') {
                    tabs.inbox.addClass('selected');
                }

                nav.find('a.selected').attr('aria-current', 'page');

                tabs.inbox.find('.slate-tab-badge').text(counts.INBOX ? counts.INBOX : '');
                tabs.junk.find('.slate-tab-badge').text(counts[junk] ? counts[junk] : '');
            },
            open_mailbox = function (mbox, e) {
                // inside the mail list switch folders without a page load
                if (rcmail.task == 'mail' && !rcmail.env.action && rcmail.message_list) {
                    e.preventDefault();
                    rcmail.command('list', mbox);
                    UI.show_list(true);
                }
            };

        tabs.junk.attr('href', link({ _task: 'mail', _mbox: junk }));
        tabs.inbox.attr('href', link({ _task: 'mail', _mbox: 'INBOX' }));
        tabs.settings.attr('href', link({ _task: 'settings' }));

        tabs.inbox.on('click', function (e) {
            open_mailbox('INBOX', e);
        });
        tabs.junk.on('click', function (e) {
            open_mailbox(junk, e);
        });

        rcmail.addEventListener('listupdate', update)
            .addEventListener('set-unread-count', update)
            .addEventListener('selectfolder', update);

        update();
    }

    /**
     * Phones: hide the bottom bar while the reading pane or compose is open.
     */
    function setup_content_state() {
        var content = $('#layout-content'),
            list = $('#layout-list, #layout-sidebar'),
            update = function () {
                var mobile = UI.is_mobile(),
                    open = mobile && list.length && !content.is('.hidden') && !list.filter(':not(.hidden)').length;
                $('body').toggleClass('slate-content-open', !!open);
            };

        if (!content.length || !list.length) {
            return;
        }

        new MutationObserver(update).observe(content[0], { attributes: true, attributeFilter: ['class'] });
        list.each(function () {
            new MutationObserver(update).observe(this, { attributes: true, attributeFilter: ['class'] });
        });
        rcmail.addEventListener('skin-resize', update);
        update();
    }

    /**
     * List header shows the current folder name (Elastic hides it on wide screens).
     */
    function setup_list_title() {
        var title = $('#messagelist-header .header-title'),
            set = function () {
                var li = rcmail.get_folder_li(rcmail.env.mailbox, '', true),
                    name = li ? $(li).children('a').first().clone().children().remove().end().text().trim() : '';

                if (rcmail.env.search_request && rcmail.env.search_scope == 'all') {
                    name = rcmail.get_label('search');
                }

                if (name) {
                    title.text(name);
                }
            };

        if (!title.length) {
            return;
        }

        rcmail.addEventListener('listupdate', set);
        set();
    }

    /**
     * Compose: options (receipts, priority, sent folder) open in a dialog.
     * The fields stay the same DOM nodes, so ui.js keeps syncing them into the form.
     */
    UI.slate_compose_options = function () {
        var holder = $('#slate-compose-options'),
            options = $('#compose-options');

        if (!options.length) {
            return false;
        }

        UI.menu_hide('compose-more-menu');

        rcmail.show_popup_dialog(options, rcmail.get_label('options'), [{
            text: rcmail.get_label('close'),
            class: 'mainaction cancel',
            click: function () {
                $(this).dialog('close');
            },
        }], {
            width: 420,
            close: function () {
                options.appendTo(holder);
                $(this).remove();
            },
        });

        return false;
    };

    function setup_compose() {
        if (rcmail.env.action != 'compose') {
            return;
        }

        // Cc / Bcc text links next to the To field
        $('a.slate-addheader').on('click', function (e) {
            e.preventDefault();
            var target = $(this).data('target');
            $('#compose_' + target).removeClass('hidden').find('.recipient-input input').focus();
            $(this).addClass('hidden');
        });

        $('#_cc, #_bcc').each(function () {
            var name = this.id.replace(/^_/, ''),
                link = $('a.slate-addheader[data-target="' + name + '"]'),
                sync = function () {
                    link.toggleClass('hidden', !$('#compose_' + name).is('.hidden'));
                };
            new MutationObserver(sync).observe($('#compose_' + name)[0], { attributes: true, attributeFilter: ['class'] });
            sync();
        });

        // show the From row only when there is more than one identity
        if ($('#_from option').length > 1) {
            $('body').addClass('slate-multi-identity');
        }

        // plugin compose toolbar buttons go into the more menu
        var holder = $('#slate-compose-plugins'),
            slot = $('#compose-more-menu li.slate-compose-plugin-slot');
        holder.children('a').each(function () {
            var a = $(this).removeClass('button');
            a.find('span.inner').removeClass('inner');
            $('<li role="menuitem">').append(a).insertBefore(slot);
        });
        holder.remove();
    }

    rcmail.addEventListener('init', function () {
        setup_compose();
        // rcmail.init() sets the default template just before this event;
        // the first list request is asynchronous, so rows are not rendered yet.
        setup_message_rows();
        setup_plugin_buttons();
        setup_folders();
        setup_filters();
        setup_context_menu();
        setup_bottomnav();
        setup_list_title();
        setup_content_state();
    });
})(jQuery);
