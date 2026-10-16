# Releasing

```sh
git tag v0.1.1
git push origin v0.1.1
```

`.github/workflows/publish.yml` publishes every package whose pubspec carries
the tag's version, in dependency order: platform interface, Linux, macOS, Windows,
`system_hotkeys`.

## One-time setup per package

1. Publish it once by hand (`flutter pub publish` in its folder), because
   pub.dev's automated-publishing settings exist only after the first upload.
2. On pub.dev: Admin → Automated publishing → GitHub Actions, repository
   `hinata-platform/system_hotkeys`, tag pattern `v{{version}}`.
3. Transfer it to the `ahmadre.com` publisher.
