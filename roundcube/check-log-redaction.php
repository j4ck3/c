<?php
// This test uses artificial callback values only. It does not contact Microsoft.
define('INSTALL_PATH', '/var/www/html/');
require INSTALL_PATH . 'program/include/iniset.php';
$rcmail = rcmail::get_instance();
$uri = '/index.php/login/oauth?code=SYNTHETIC_CODE_FOR_LOG_TEST&state=SYNTHETIC_STATE_FOR_LOG_TEST';
$_SERVER['REQUEST_URI'] = $uri;
$_SERVER['REQUEST_METHOD'] = 'GET';
$expectedRedaction = in_array('--expect-redacted', $argv, true);
$logDirectory = sys_get_temp_dir() . '/roundcube-log-test-' . bin2hex(random_bytes(6));
mkdir($logDirectory, 0700);
$rcmail->config->set('log_driver', 'file');
$rcmail->config->set('log_dir', $logDirectory);
$rcmail->config->set('log_file_ext', '.log');
// Invoke the same log_bug path used by HTTP raise_error. CLI raise_error deliberately uses a different stderr path.
rcube::log_bug(['type' => 'php', 'message' => 'Synthetic OAuth callback log test']);
$output = file_get_contents($logDirectory . '/errors.log');
unlink($logDirectory . '/errors.log');
rmdir($logDirectory);
$hasCode = str_contains($output, 'SYNTHETIC_CODE_FOR_LOG_TEST');
$hasState = str_contains($output, 'SYNTHETIC_STATE_FOR_LOG_TEST');
if (!$expectedRedaction) {
    if (!$hasCode || !$hasState) {
        fwrite(STDERR, "Could not reproduce callback query in application error log.\n");
        exit(1);
    }
    echo "REPRODUCED: artificial callback code and state reach application error logs without a redaction hook.\n";
    exit(0);
}
if ($hasCode || $hasState || !str_contains($output, '/index.php/login/oauth?[redacted]') || !str_contains($output, 'Synthetic OAuth callback log test')) {
    fwrite(STDERR, "Application error log did not redact the callback query while preserving the error.\n");
    exit(1);
}
$plugin = $rcmail->plugins->get_plugin('private_log_redaction');
if (!$plugin) {
    fwrite(STDERR, "Redaction plugin is not loaded.\n");
    exit(1);
}
$args = ['name' => 'errors', 'date' => 'synthetic-date', 'abort' => false, 'line' => 'Synthetic error (GET ' . $uri . ')'];
$result = $plugin->redact($args);
if ($result !== array_merge($args, ['line' => 'Synthetic error (GET /index.php/login/oauth?[redacted])'])) {
    fwrite(STDERR, "Redaction changed unrelated log metadata.\n");
    exit(1);
}
$_SERVER['REQUEST_URI'] = '/index.php';
if ($plugin->redact($args) !== $args) {
    fwrite(STDERR, "Query-free request unexpectedly changed the log entry.\n");
    exit(1);
}
echo "PASS Roundcube application error hook removes synthetic OAuth code/state, preserves error context and log metadata, and leaves query-free logs unchanged.\n";
