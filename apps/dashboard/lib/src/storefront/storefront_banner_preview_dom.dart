// Minimal browser bindings for this render-only frame; no package dependency.
import 'dart:js_interop';

@JS('document')
external BannerPreviewDocument get bannerPreviewDocument;
@JS('window')
external BannerPreviewWindow get bannerPreviewWindow;

extension type BannerPreviewWindow(JSObject _) implements JSObject {
  external int requestAnimationFrame(JSFunction callback);
  external BannerPreviewStyle getComputedStyle(BannerPreviewElement element);
}

extension type BannerPreviewDocument(JSObject _) implements JSObject {
  external String get baseURI;
  external BannerPreviewElement createElement(String tag);
  external BannerPreviewElement? querySelector(String selector);
  external BannerPreviewNodes querySelectorAll(String selector);
  external BannerPreviewFonts get fonts;
}

extension type BannerPreviewElement(JSObject _) implements JSObject {
  external BannerPreviewStyle get style;
  external bool get isConnected;
  external void setAttribute(String name, String value);
  external void addEventListener(String type, JSFunction callback);
  external void removeEventListener(String type, JSFunction callback);
  external BannerPreviewRect getBoundingClientRect();
  external void remove();
}

extension type BannerPreviewFrame(JSObject _) implements BannerPreviewElement {
  external BannerPreviewDocument? get contentDocument;
  external set srcdoc(String value);
}

extension type BannerPreviewImage(JSObject _) implements BannerPreviewElement {
  external int get naturalWidth;
  external int get naturalHeight;
  external bool get complete;
}

extension type BannerPreviewStyle(JSObject _) implements JSObject {
  external void setProperty(String name, String value);
  external String getPropertyValue(String name);
}

extension type BannerPreviewRect(JSObject _) implements JSObject {
  external double get width;
  external double get height;
  external double get bottom;
}

extension type BannerPreviewNodes(JSObject _) implements JSObject {
  external int get length;
  external BannerPreviewElement? item(int index);
}

extension type BannerPreviewFonts(JSObject _) implements JSObject {
  external JSPromise<BannerPreviewFonts> get ready;
  external void addEventListener(String type, JSFunction callback);
  external void removeEventListener(String type, JSFunction callback);
}

@JS('ResizeObserver')
extension type BannerPreviewResizeObserver._(JSObject _) implements JSObject {
  external factory BannerPreviewResizeObserver(JSFunction callback);
  external void observe(BannerPreviewElement element);
  external void disconnect();
}
