// Stream.io configuration — same project as soocher-web.
// Get the API key from your Stream dashboard (https://getstream.io/dashboard)
// and replace the placeholder below.
class StreamConfig {
  // TODO: Replace with your NEXT_PUBLIC_STREAM_API_KEY value
  static const String apiKey = 'z889gbfk8j79';

  // Token backend — same endpoint the web app uses
  static const String tokenEndpoint = 'https://stream.soocher.in/video-token';
  static const String tokenFallback  = 'https://stream.soocher.in/token';

  // Firestore REST — to read consultation.extras.streamCallId
  static const String firestoreProject = 'soocherv2';
  static const String firestoreApiKey  = 'AIzaSyCsFUxf29C-VSN_04eusIluvQNS8Yf3dPo';
}
