import 'package:flutter/material.dart';

import '../admin_modules/admin_shell.dart';
import '../api.dart';

// There's no sign-in: the app runs on dummy data only (lib/demo_server.dart), in development and deployed builds alike,
// so no real customer data ever reaches it. What used to be the sign-in screen is gone; this is what remains of
// "signing out": back to the start of the admin console. (A session error can't happen on the demo server, so in
// practice nothing calls it.)

Future<void> signOut(BuildContext context, {String? message}) async {
  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => AdminShell(api: AdminApi.demo())), (_) => false);
}
