<?php

/**
 * Slate prefetch support.
 *
 * The Slate skin preloads message previews in hidden iframes so a click shows the
 * message at once. Those requests carry `_prefetch=1`. For them this plugin makes the
 * preview side-effect free:
 *
 * - the message is not marked as read (mail_read_time = -1),
 * - no read receipt (MDN) is sent or asked for (mdn_requests = 2),
 * - remote images stay blocked whatever the user preference (show_images = 0).
 *
 * Slate marks the message as read itself when the user opens it, and drops a
 * prefetched preview that would have asked for a read receipt.
 */
class slate_prefetch extends rcube_plugin
{
    public $task = 'mail';

    #[\Override]
    public function init()
    {
        $rcmail = rcmail::get_instance();

        // The message list marks prefetched messages as read itself; give it the user's setting.
        if ($rcmail->action === '' || $rcmail->action === 'index') {
            $rcmail->output->set_env('slate_mail_read_time', (int) $rcmail->config->get('mail_read_time'));

            return;
        }

        if ($rcmail->action !== 'preview' || empty($_GET['_prefetch'])) {
            return;
        }

        $rcmail->config->set('mail_read_time', -1);
        $rcmail->config->set('mdn_requests', 2);
        $rcmail->config->set('show_images', 0);

        // Let the page know it was prefetched (Slate checks this before showing the frame).
        $rcmail->output->set_env('slate_prefetched', true);
    }
}
