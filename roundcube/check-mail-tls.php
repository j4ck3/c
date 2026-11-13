<?php
// This check opens TLS connections without sending any mailbox credentials or email.
function requireCheck($condition, $message) {
    if (!$condition) {
        fwrite(STDERR, $message . "\n");
        exit(1);
    }
}
function smtpReply($socket) {
    $result = '';
    while (($line = fgets($socket)) !== false) {
        $result .= $line;
        if (strlen($line) >= 4 && $line[3] === ' ') {
            break;
        }
    }
    return $result;
}
$imapHost = 'outlook.office365.com';
$context = stream_context_create(['ssl' => ['verify_peer' => true, 'verify_peer_name' => true, 'allow_self_signed' => false, 'peer_name' => $imapHost]]);
$imap = stream_socket_client('ssl://' . $imapHost . ':993', $errno, $error, 20, STREAM_CLIENT_CONNECT, $context);
requireCheck($imap !== false, 'IMAP TLS connection failed: ' . $error);
stream_set_timeout($imap, 20);
requireCheck(str_starts_with(fgets($imap) ?: '', '* OK'), 'Unexpected IMAP greeting.');
fwrite($imap, "a1 CAPABILITY\r\n");
$capabilities = '';
while (($line = fgets($imap)) !== false) {
    $capabilities .= $line;
    if (str_starts_with($line, 'a1 ')) break;
}
requireCheck(str_contains($capabilities, 'AUTH=XOAUTH2'), 'IMAP does not advertise XOAUTH2.');
fwrite($imap, "a2 LOGOUT\r\n");
fclose($imap);
echo "PASS IMAP 993: verified TLS certificate and hostname, Microsoft greeting, XOAUTH2 advertised.\n";

$smtpHost = 'smtp-mail.outlook.com';
$context = stream_context_create(['ssl' => ['verify_peer' => true, 'verify_peer_name' => true, 'allow_self_signed' => false, 'peer_name' => $smtpHost]]);
$smtp = stream_socket_client('tcp://' . $smtpHost . ':587', $errno, $error, 20, STREAM_CLIENT_CONNECT, $context);
requireCheck($smtp !== false, 'SMTP connection failed: ' . $error);
stream_set_timeout($smtp, 20);
requireCheck(str_starts_with(smtpReply($smtp), '220'), 'Unexpected SMTP greeting.');
fwrite($smtp, "EHLO mail.netbird.hjacke.com\r\n");
requireCheck(str_contains(smtpReply($smtp), 'STARTTLS'), 'SMTP does not advertise STARTTLS.');
fwrite($smtp, "STARTTLS\r\n");
requireCheck(str_starts_with(smtpReply($smtp), '220'), 'SMTP refused STARTTLS.');
requireCheck(stream_socket_enable_crypto($smtp, true, STREAM_CRYPTO_METHOD_TLS_CLIENT) === true, 'SMTP TLS certificate/hostname verification failed.');
fwrite($smtp, "EHLO mail.netbird.hjacke.com\r\n");
requireCheck(str_contains(smtpReply($smtp), 'XOAUTH2'), 'Encrypted SMTP does not advertise XOAUTH2.');
fwrite($smtp, "QUIT\r\n");
fclose($smtp);
echo "PASS SMTP 587: mandatory STARTTLS, verified certificate and hostname, XOAUTH2 advertised.\n";
echo "NOT TESTED: mailbox login, message read, send, or OAuth refresh. These require owner consent.\n";
