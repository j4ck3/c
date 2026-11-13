<?php
// Roundcube remains behind the NetBird-only HTTPS listener.
$config['use_https'] = true;
$config['force_https'] = false;
$config['trusted_host_patterns'] = ['^mail\.netbird\.hjacke\.com$'];
$proxyAddress = gethostbyname('dockhand-netbird-proxy');
$config['proxy_whitelist'] = filter_var($proxyAddress, FILTER_VALIDATE_IP) ? [$proxyAddress] : [];
$config['session_samesite'] = 'Lax';
$config['enable_installer'] = false;
$config['enable_spellcheck'] = false;
$config['cipher_method'] = 'AES-256-CBC';
$persistentKey = file_get_contents('/run/secrets/des_key');
if ($persistentKey === false || strlen($persistentKey) !== 32) {
    throw new RuntimeException('The persistent Roundcube encryption key is missing or invalid.');
}
$config['des_key'] = $persistentKey;
$config['db_dsnw'] = 'sqlite:////var/roundcube/db/sqlite.db?mode=0600';
$config['session_lifetime'] = 30;
$config['login_autocomplete'] = 0;
$config['log_driver'] = 'stdout';
$config['imap_debug'] = false;
$config['smtp_debug'] = false;
$config['oauth_debug'] = false;
$config['smtp_timeout'] = 30;
$config['imap_timeout'] = 30;
$config['imap_auth_type'] = 'XOAUTH2';
$config['smtp_auth_type'] = 'XOAUTH2';
$config['smtp_user'] = '%u';
$config['smtp_pass'] = '%p';
$config['imap_conn_options'] = ['ssl' => ['verify_peer' => true, 'verify_peer_name' => true, 'allow_self_signed' => false]];
$config['smtp_conn_options'] = ['ssl' => ['verify_peer' => true, 'verify_peer_name' => true, 'allow_self_signed' => false]];

// Read secret files directly rather than interpolating their contents into generated PHP or Docker environment variables.
$clientIdFile = '/run/secrets/microsoft_client_id';
$clientSecretFile = '/run/secrets/microsoft_client_secret';
$clientId = is_readable($clientIdFile) ? trim(file_get_contents($clientIdFile)) : '';
$clientSecret = is_readable($clientSecretFile) ? trim(file_get_contents($clientSecretFile)) : '';
$oauthReady = $clientId !== '' && $clientSecret !== '';
$config['product_name'] = $oauthReady ? 'Roundcube' : 'Roundcube - Microsoft setup required';
$config['oauth_provider'] = $oauthReady ? 'outlook' : null;
$config['oauth_provider_name'] = 'Microsoft';
$config['oauth_client_id'] = $clientId;
$config['oauth_client_secret'] = $clientSecret;
$config['oauth_auth_uri'] = 'https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize';
$config['oauth_token_uri'] = 'https://login.microsoftonline.com/consumers/oauth2/v2.0/token';
$config['oauth_scope'] = 'https://outlook.office.com/IMAP.AccessAsUser.All https://outlook.office.com/SMTP.Send openid profile email offline_access';
$config['oauth_identity_fields'] = ['email', 'preferred_username'];
$config['oauth_identity_uri'] = null;
$config['oauth_pkce'] = 'S256';
$config['oauth_auth_type'] = 'XOAUTH2';
$config['oauth_verify_peer'] = true;
$config['oauth_cache'] = 'db';
$config['oauth_login_redirect'] = $oauthReady;
