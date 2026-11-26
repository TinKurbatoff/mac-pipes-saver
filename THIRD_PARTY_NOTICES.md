# Third-party notices

This project is released into the public domain under the Unlicense (see `LICENSE`).
The component below is the only exception: it stays under its own MIT license.

## Utah teapot data (`Sources/UtahTeapotData.swift`)

The Bezier patch data for the Utah teapot (Martin Newell, 1975; Blinn-scaled) comes from
three.js r98, `examples/js/geometries/TeapotBufferGeometry.js` by Eric Haines. The
1j01/pipes example vendors the same file. Only the numeric data was taken. The
tessellation code in `Sources/Teapot.swift` is an independent implementation.

The MIT License

Copyright © 2010-2018 three.js authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
