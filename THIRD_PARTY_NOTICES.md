# Third-party notices

ScreenMate includes or links the following open-source software. When the app
is distributed to anyone (TestFlight, App Store, ad hoc), show these notices
in the app (for example a "오픈소스 라이선스" screen) and keep this file
up to date with `Packages/ScreenMateKit/Package.resolved`.

| Component | Version | License | How it is used |
| --- | --- | --- | --- |
| [rootshell-vnc](https://github.com/kitknox/rootshell-vnc) | 0.1.8 (+2 small patches) | MIT | Vendored source in `Vendor/rootshell-vnc` |
| [BigInt](https://github.com/attaswift/BigInt) | 5.7.0 | MIT | SwiftPM dependency of rootshell-vnc |
| [SwiftNIO](https://github.com/apple/swift-nio) | 2.95.0 | Apache-2.0 | SwiftPM dependency |
| [SwiftNIO SSL](https://github.com/apple/swift-nio-ssl) | 2.36.0 | Apache-2.0; bundles BoringSSL (OpenSSL/ISC-style licenses) | SwiftPM dependency |
| [SwiftNIO Transport Services](https://github.com/apple/swift-nio-transport-services) | 1.26.0 | Apache-2.0 | SwiftPM dependency |
| [Swift Atomics](https://github.com/apple/swift-atomics) | 1.3.x | Apache-2.0 | Transitive |
| [Swift Collections](https://github.com/apple/swift-collections) | 1.x | Apache-2.0 | Transitive |
| [Swift System](https://github.com/apple/swift-system) | 1.x | Apache-2.0 | Transitive |

The exact resolved versions are in `Packages/ScreenMateKit/Package.resolved`.

## rootshell-vnc

```
MIT License

Copyright (c) 2026 Rootshell LLC, Kit Knox

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The full license texts of the SwiftPM dependencies are in their repositories
(fetched into the build's `checkouts/` directory).
