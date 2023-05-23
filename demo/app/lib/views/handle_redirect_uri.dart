import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:app/widgets/primary_button.dart';
import 'dart:developer';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:app/demo_method_channel.dart';
import 'package:app/widgets/common_title_appbar.dart';
import 'package:app/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/models/activity_data_object.dart';
import 'package:app/models/credential_data.dart';
import 'credential_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:uni_links/uni_links.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class HandleRedirectUri extends StatefulWidget {
  Uri uri;
  HandleRedirectUri(this.uri);

  @override
  State<HandleRedirectUri> createState() => HandleRedirectUriState();
}

class HandleRedirectUriState extends State<HandleRedirectUri> {
  Uri? _redirectUri;
  Object? _err;

  var WalletSDKPlugin = MethodChannelWallet();
  final StorageService _storageService = StorageService();
  final Future<SharedPreferences> prefs = SharedPreferences.getInstance();
  var userDIDId = '';
  var userDIDDoc = '';

  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _launchUrl(widget.uri);
    _handleIncomingLinks();
  }


  _launchUrl(Uri uri) async {
    final initialUri = await getInitialUri();
    if (!await launch(uri.toString(), forceSafariVC: false)) {
      throw 'Could not launch $uri';
    }
  }

  void _handleIncomingLinks() {
    if (!kIsWeb) {
      _sub = uriLinkStream.listen((Uri? uri) {
        if (!mounted) return;
        log("received redirect uri $uri");
        setState(() {
          _redirectUri = uri;
          _err = null;
        });
      }, onError: (Object err) {
        if (!mounted) return;
        setState(() {
          _redirectUri = null;
          if (err is FormatException) {
            _err = err;
          } else {
            _err = null;
          }
        });
      });
    }
  }


  Future<String?> _createDid() async {
    final SharedPreferences pref = await prefs;
    var didType = pref.getString('didType');
    didType = didType ?? "ion";
    var keyType = pref.getString('keyType');
    keyType = keyType ?? "ED25519";
    var didResolution = await WalletSDKPlugin.createDID(didType, keyType);
    var didDocEncoded = json.encode(didResolution!);
    Map<String, dynamic> responseJson = json.decode(didDocEncoded);
    var didID = responseJson["did"];
    var didDoc = responseJson["didDoc"];
    setState(() {
      userDIDId = didID;
      userDIDDoc = didDoc;
    });
    return didID;
  }

  launchCredPreview() async {
    final SharedPreferences pref = await prefs;
    await _createDid();
    pref.setString('userDID',userDIDId);
    pref.setString('userDIDDoc',userDIDDoc);
    if (_redirectUri != null) {
      var credentials = await WalletSDKPlugin.requestCredentialWithAuth(_redirectUri.toString());
      String? issuerURI = await WalletSDKPlugin.issuerURI();
      var resolvedCredentialDisplay = await WalletSDKPlugin.serializeDisplayData([credentials], issuerURI!);
      log("resolvedCredentialDisplay -> $resolvedCredentialDisplay");
      var renderedCredDisplay = await WalletSDKPlugin.resolveCredentialDisplay(resolvedCredentialDisplay!);
      var activities = await WalletSDKPlugin.storeActivityLogger();
      var credID = await WalletSDKPlugin.getCredID([credentials]);
      _storageService.addActivities(ActivityDataObj(credID!, activities));
      pref.setString("credID", credID);
      _navigateToCredPreviewScreen(credentials, issuerURI, resolvedCredentialDisplay!, userDIDId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      body: new Column(
        children: <Widget>[
          FutureBuilder(
            future: launchCredPreview(),
            builder: (BuildContext context, AsyncSnapshot snapshot){
              if(snapshot.hasData) {
                return launchCredPreview();
              }
              return SizedBox(
                height: MediaQuery.of(context).size.height / 1.3,
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            },
          )
        ],
     )
    );
  }

 _navigateToCredPreviewScreen(String credentialResp, String issuerURI, String credentialDisplayData, String didID) async {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => CredentialPreview(credentialData: CredentialData(rawCredential: credentialResp, issuerURL: issuerURI, credentialDisplayData: credentialDisplayData, credentialDID: didID),)));
  });
}
}