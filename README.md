# Resecentrum: Journey planner for Västtrafik

Resecentrum is a journey planner app for public transport in Västra Götaland, Sweden, operated by Västtrafik.
It is built with Flutter and is available for both Android and iOS.
You can now get it on Google Play, and it will soon be released to Apple App Store.
The app is only available in Swedish.

<a href='https://play.google.com/store/apps/details?id=ga.edvin.resecentrum'><img alt='Get it on Google Play' src='https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png' height='80px'/></a>

## Build notes

Run ```flutter pub run build_runner build``` for code generation.

When building, assign API keys with ```--dart-define```.  
For example ```flutter build apk --dart-define AUTH_KEY=<insert-auth-key> --dart-define AUTH_SECRET=<insert-auth-secret>```.


<sub>Google Play and the Google Play logo are trademarks of Google LLC.</sub>
