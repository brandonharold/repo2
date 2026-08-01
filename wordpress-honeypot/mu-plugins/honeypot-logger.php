<?php
/**
 * Plugin Name: Honeypot Logger
 * Description: Records login attempts, XML-RPC calls, sensitive REST API
 *              probing, and recon-flavored 404s as JSON lines, for
 *              honeypot research. Deliberately does not log passwords.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

if ( ! defined( 'HONEYPOT_LOG_DIR' ) ) {
	define( 'HONEYPOT_LOG_DIR', '/var/log/wp-honeypot' );
}

function honeypot_logger_write( $type, array $extra = array() ) {
	$log_file = rtrim( HONEYPOT_LOG_DIR, '/' ) . '/events.log';

	$event = array_merge(
		array(
			'ts'   => date( 'c' ),
			'type' => $type,
			'ip'   => isset( $_SERVER['REMOTE_ADDR'] ) ? $_SERVER['REMOTE_ADDR'] : '',
			'ua'   => isset( $_SERVER['HTTP_USER_AGENT'] ) ? substr( $_SERVER['HTTP_USER_AGENT'], 0, 300 ) : '',
			'uri'  => isset( $_SERVER['REQUEST_URI'] ) ? substr( $_SERVER['REQUEST_URI'], 0, 500 ) : '',
		),
		$extra
	);

	$line = wp_json_encode( $event ) . "\n";
	@file_put_contents( $log_file, $line, FILE_APPEND | LOCK_EX );
}

// --- Login attempts. Username only — never log submitted passwords. ---
add_action(
	'wp_login_failed',
	function ( $username ) {
		honeypot_logger_write( 'login_failed', array( 'username' => substr( (string) $username, 0, 100 ) ) );
	}
);

add_action(
	'wp_login',
	function ( $user_login ) {
		// This should essentially never fire — the site is administered via
		// WP-CLI, not the web UI. Treat any hit as high severity.
		honeypot_logger_write(
			'login_success',
			array(
				'username' => substr( (string) $user_login, 0, 100 ),
				'severity' => 'critical',
			)
		);
	}
);

// --- XML-RPC: log every call, and remove methods that let this box be
// abused to attack third parties (pingback amplification) or brute-force
// many credentials in a single request (multicall). ---
add_action(
	'xmlrpc_call',
	function ( $method ) {
		$dangerous = in_array(
			$method,
			array( 'pingback.ping', 'pingback.extensions.getPingbacks', 'system.multicall' ),
			true
		);
		honeypot_logger_write(
			'xmlrpc_call',
			array(
				'method'   => $method,
				'severity' => $dangerous ? 'critical' : 'info',
			)
		);
	}
);

add_filter(
	'xmlrpc_methods',
	function ( $methods ) {
		unset( $methods['pingback.ping'], $methods['pingback.extensions.getPingbacks'], $methods['system.multicall'] );
		return $methods;
	}
);

// --- REST API: flag unauthenticated probing of endpoints that enumerate
// users or other sensitive data. ---
add_filter(
	'rest_authentication_errors',
	function ( $result ) {
		$route = isset( $GLOBALS['wp']->query_vars['rest_route'] ) ? $GLOBALS['wp']->query_vars['rest_route'] : '';
		if ( ! empty( $_SERVER['REQUEST_URI'] ) && false !== strpos( $_SERVER['REQUEST_URI'], '/wp-json/wp/v2/users' ) && ! is_user_logged_in() ) {
			honeypot_logger_write( 'rest_user_enum', array( 'route' => $route ) );
		}
		return $result;
	}
);

// --- Recon 404s: common scanner/exploit-probe paths. ---
add_action(
	'template_redirect',
	function () {
		if ( ! is_404() ) {
			return;
		}

		$uri     = isset( $_SERVER['REQUEST_URI'] ) ? $_SERVER['REQUEST_URI'] : '';
		$signals = array(
			'.env',
			'wp-config.php.bak',
			'wp-config.php~',
			'.git/',
			'phpmyadmin',
			'xmlrpc.php',
			'/wp-content/uploads/',
			'.sql',
			'shell.php',
			'wp-content/debug.log',
		);

		foreach ( $signals as $needle ) {
			if ( false !== stripos( $uri, $needle ) ) {
				honeypot_logger_write( 'recon_404', array( 'matched' => $needle ) );
				return;
			}
		}
	}
);
