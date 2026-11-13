<?php
// Slate skin: black, always-dark UI with a one-line message list.
// ROUNDCUBEMAIL_SKIN stays elastic: the entrypoint would try to install a missing skin with
// composer before the post-setup task copies Slate in. Rollback: move this file out of config/
// and recreate the container.
$config['skin'] = 'slate';
$config['dont_override'] = array_values(array_unique(array_merge((array) ($config['dont_override'] ?? []), ['skin'])));
$config['layout'] = 'widescreen';
$config['message_sort_col'] = 'date';
$config['message_sort_order'] = 'DESC';

// Junk/Not junk live in the "more" menu instead of the toolbar.
$config['markasjunk_toolbar'] = false;
// Outlook.com has no learning backend here; only move the message.
$config['markasjunk_learning_driver'] = null;
$config['markasjunk_spam_flag'] = false;
$config['markasjunk_ham_flag'] = false;

// Outlook.com's archive folder; the user can change it under Settings > Preferences > Special folders.
$config['archive_mbox'] = 'Archive';
