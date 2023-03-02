# :robot: ChatGPT@Home

Yet another ChatGPT clone in Flutter, now for the phones. (WIP)

- Material 3
- Render results in Markdown
- Dictate in any device-supported language (one at a time)
- Self-service (put in your own API key)

<img src="site/main_screen.png" width="300" alt="Main screen" />

## :hammer: Building

### From source

Fill out your config file from `define.json.template`, then invoke `flutter run`:

```shell
flutter run --dart-define-from-file define.json
```