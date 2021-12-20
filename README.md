# Resecentrum: Journey planner for Västtrafik

Resecentrum is a journey planner app for public transport in Västra Götaland, Sweden, operated by Västtrafik.
It is built with Flutter and is available for both Android and iOS.
It will soon be released to both Google Play Store and Apple App Store.
The app is only available in Swedish.

## Build notes

Run ```flutter pub run build_runner build``` for code generation.

When building, assign API keys with ```--dart-define```.  
For example ```flutter build apk --dart-define AUTH_KEY=<insert-auth-key> --dart-define AUTH_SECRET=<insert-auth-secret>```.


