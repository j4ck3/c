<?php
// IMAP folder/index cache in the private Redis container (roundcube-redis).
// Message bodies are not cached: Outlook.com has no QRESYNC/CONDSTORE, which
// Roundcube's messages_cache requires. Roundcube keeps working without a cache if
// Redis is down. Rollback: move this file out of config/ and recreate the container.
$config['redis_hosts'] = ['roundcube-redis:6379'];
$config['imap_cache'] = 'redis';
$config['imap_cache_ttl'] = '10d';
$config['messages_cache'] = false;
