<?php
// Keep OAuth callback query values out of Roundcube application logs.
class private_log_redaction extends rcube_plugin
{
    public function onload(): void
    {
        $this->add_hook('write_log', [$this, 'redact']);
    }

    public function init(): void
    {
    }

    public function redact(array $args): array
    {
        $uri = strip_tags((string) ($_SERVER['REQUEST_URI'] ?? ''));
        $query = strpos($uri, '?');
        if ($query !== false) {
            $args['line'] = str_replace($uri, substr($uri, 0, $query) . '?[redacted]', $args['line']);
        }

        return $args;
    }
}
