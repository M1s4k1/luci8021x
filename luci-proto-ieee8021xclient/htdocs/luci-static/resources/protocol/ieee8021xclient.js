'use strict';
'require network';
'require uci';
'require form';

network.registerProtocol('ieee8021xclient', {
	getI18n: function() {
		return _('IEEE 802.1X Client');
	},

	getIfname: function() {
		return this._ubus('l3_device') || this._ubus('device');
	},

	getPackageName: function() {
		return 'ieee8021xclient';
	},

	isFloating: function() {
		return false;
	},

	isVirtual: function() {
		return false;
	},

	getDevices: function() {
		return null;
	},

	containsDevice: function(ifname) {
		return (network.getIfnameOf(this.sid) == ifname);
	},

	renderFormOptions: function(s) {
		var o;

		o = s.taboption('general', form.Value, 'eap', _('EAP method'),
			_('Outer EAP method, e.g. PEAP, TTLS, TLS or MD5. Leave empty to ' +
			  'let wpa_supplicant negotiate any compiled-in method.'));
		o.placeholder = 'PEAP';

		o = s.taboption('general', form.Value, 'identity', _('Identity'),
			_('Username sent to the authentication server.'));
		o.rmempty = false;
		o.optional = false;

		o = s.taboption('general', form.Value, 'anonymous_identity', _('Anonymous identity'),
			_('Outer identity sent in clear text. Only useful with PEAP or TTLS.'));

		o = s.taboption('general', form.Value, 'password', _('Password'),
			_('Password or, with EAP-TLS, not needed if the private key is used.'));
		o.password = true;

		o = s.taboption('general', form.ListValue, 'eapol_version', _('EAPOL version'),
			_('EAPOL protocol version. Most campus and enterprise networks use 2.'));
		o.value('', _('Use default'));
		o.value('1', _('Version 1'));
		o.value('2', _('Version 2'));

		o = s.taboption('general', form.Flag, 'eap_workaround', _('EAP workaround'),
			_('Enable wpa_supplicant workarounds for misbehaving authentication servers.'));
		o.default = '1';

		o = s.taboption('advanced', form.Value, 'phase1', _('Phase 1 options'),
			_('Outer authentication parameters, e.g. peaplabel=0 or allow_canned_success=1.'));

		o = s.taboption('advanced', form.Value, 'phase2', _('Phase 2 options'),
			_('Inner authentication, e.g. auth=MSCHAPV2 for PEAP or autheap=TLS for TTLS.'));

		o = s.taboption('advanced', form.Value, 'ca_cert', _('CA certificate'),
			_('Path to the trusted CA certificate file (PEM or DER) on this device.'));

		o = s.taboption('advanced', form.Value, 'client_cert', _('Client certificate'),
			_('Path to the client certificate file (PEM or DER).'));

		o = s.taboption('advanced', form.Value, 'private_key', _('Private key'),
			_('Path to the client private key file.'));

		o = s.taboption('advanced', form.Value, 'private_key_passwd', _('Private key password'),
			_('Password protecting the private key file.'));
		o.password = true;

		o = s.taboption('advanced', form.Value, 'dh_file', _('DH/DSA parameters file'),
			_('Path to the DH/DSA parameters file (PEM). Rarely needed.'));

		o = s.taboption('advanced', form.Value, 'subject_match', _('Subject match'),
			_('Substring that must be present in the subject of the server certificate.'));

		o = s.taboption('advanced', form.Value, 'ca_cert2', _('CA certificate (phase 2)'),
			_('Like CA certificate, but for the inner EAP-TTLS or EAP-PEAP authentication.'));

		o = s.taboption('advanced', form.Value, 'client_cert2', _('Client certificate (phase 2)'),
			_('Like client certificate, but for the inner authentication.'));

		o = s.taboption('advanced', form.Value, 'private_key2', _('Private key (phase 2)'),
			_('Like private key, but for the inner authentication.'));

		o = s.taboption('advanced', form.Value, 'private_key2_passwd', _('Private key password (phase 2)'),
			_('Like private key password, but for the inner authentication.'));
		o.password = true;

		o = s.taboption('advanced', form.Value, 'dh_file2', _('DH/DSA parameters file (phase 2)'),
			_('Like DH/DSA parameters file, but for the inner authentication.'));

		o = s.taboption('advanced', form.Value, 'subject_match2', _('Subject match (phase 2)'),
			_('Like subject match, but for the inner authentication.'));
	}
});
