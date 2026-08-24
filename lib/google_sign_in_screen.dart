import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'google_auth_native.dart';
import 'webview_host.dart';

/// WebView 밖에서 Google 계정 선택창을 띄움 (activity result 가 안 씹히게)
class GoogleSignInScreen extends StatefulWidget {
  const GoogleSignInScreen({super.key});

  @override
  State<GoogleSignInScreen> createState() => _GoogleSignInScreenState();
}

class _GoogleSignInScreenState extends State<GoogleSignInScreen> {
  var _busy = true;
  String? _error;
  var _errorSentToWeb = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _signIn();
    });
  }

  Future<void> _notifyWebError(String code) async {
    if (_errorSentToWeb || code == 'cancelled') return;
    _errorSentToWeb = true;
    await WebViewHost.instance.dispatchGoogleSignInError(code);
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
      _errorSentToWeb = false;
    });
    try {
      final token = await obtainGoogleIdToken();
      if (!mounted) return;
      Navigator.of(context).pop(token ?? '');
    } catch (e, st) {
      debugPrint('GoogleSignInScreen failed: $e\n$st');
      final code = friendlyGoogleError(e);
      await _notifyWebError(code);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = code;
      });
    }
  }

  String _errorText(String code) {
    switch (code) {
      case 'developer_error':
        return 'Play 앱 서명 SHA-1이 Google Cloud\nAndroid 클라이언트에 없어요.\nCloud Console에 추가한 뒤 재설치해 주세요.';
      case 'play_services':
        return 'Google Play 서비스 / 계정 설정을 확인해 주세요.';
      case 'network':
        return '네트워크를 확인해 주세요.';
      case 'no_id_token':
        return 'Google 토큰을 받지 못했어요.\nSHA-1과 Web Client ID를 확인해 주세요.';
      case 'timeout':
        return '계정 창이 안 떴거나 너무 오래 걸렸어요.';
      case 'cancelled':
        return '로그인이 취소됐어요.';
      default:
        return 'Google 로그인에 실패했어요.\n$code';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F3EE),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF3D3229),
        title: const Text('Google 로그인'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(''),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_busy) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                const Text(
                  'Google 계정 창을 띄우는 중…',
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.45, fontSize: 15),
                ),
              ],
              if (_error != null) ...[
                Text(
                  _errorText(_error!),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    height: 1.45,
                    fontSize: 15,
                    color: Color(0xFFB42318),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _signIn,
                    child: const Text('다시 시도'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
