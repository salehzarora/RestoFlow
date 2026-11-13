import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'storefront_banner_preview_document.dart';
import 'storefront_banner_preview_dom.dart';
import 'storefront_banner_preview_geometry.dart';

const _viewType = 'bizbot-storefront-banner-preview';
bool _registered = false;
final _frames = <int, BannerPreviewFrame>{};
void _style(BannerPreviewElement node, String key, String value) =>
    node.style.setProperty(key, value);
void _register() {
  if (_registered) return;
  ui_web.platformViewRegistry.registerViewFactory(_viewType, (int id) {
    final frame = BannerPreviewFrame(
      bannerPreviewDocument.createElement('iframe'),
    );
    frame.setAttribute('sandbox', 'allow-same-origin');
    frame.setAttribute('tabindex', '-1');
    frame.setAttribute('aria-hidden', 'true');
    frame.setAttribute('referrerpolicy', 'no-referrer');
    frame.setAttribute('title', 'Storefront banner preview');
    _style(frame, 'width', '390px');
    _style(frame, 'height', '500px');
    _style(frame, 'border', '0');
    _style(frame, 'display', 'block');
    _style(frame, 'pointer-events', 'none');
    _frames[id] = frame;
    return frame;
  });
  _registered = true;
}

/// Browser layout at a real logical viewport width, scaled only after layout.
/// No session/API bridge, scripts, forms, navigation or gesture interception.
class StorefrontBannerPreviewFrame extends StatefulWidget {
  const StorefrontBannerPreviewFrame({
    required this.data,
    required this.focalX,
    required this.focalY,
    required this.logicalWidth,
    required this.onCrop,
    super.key,
  });
  final Map<String, Object?> data;
  final int focalX, focalY;
  final double logicalWidth;
  final ValueChanged<StorefrontBannerCrop> onCrop;
  @override
  State<StorefrontBannerPreviewFrame> createState() => _FrameState();
}

class _FrameState extends State<StorefrontBannerPreviewFrame> {
  BannerPreviewFrame? _frame;
  int? _viewId;
  int _generation = 0;
  bool _measureQueued = false;
  double _height = 500;
  String? _signature;
  BannerPreviewResizeObserver? _resizeObserver;
  BannerPreviewFonts? _fontSet;
  JSFunction? _fontCallback, _loadCallback;
  final _imageEvents = <(BannerPreviewElement, String, JSFunction)>[];
  StorefrontBannerCrop? _lastCrop;
  double get _width => widget.logicalWidth.isFinite
      ? widget.logicalWidth.clamp(320, 1920).toDouble()
      : 390;
  Uri get _assetBase => Uri.parse(
    bannerPreviewDocument.baseURI,
  ).resolve('storefront-banner-preview/');
  BannerPreviewDocument? get _document => _frame?.contentDocument;

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(covariant StorefrontBannerPreviewFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_frame == null) return;
    if (storefrontBannerPresentationSignature(widget.data) != _signature) {
      _setDocument();
    } else {
      _style(_frame!, 'width', '${_width}px');
      _setFocal();
      _queueMeasure();
    }
  }

  void _created(int id) {
    final frame = _frames[id];
    if (!mounted || frame == null) {
      _frames.remove(id);
      return;
    }
    _viewId = id;
    _frame = frame;
    _loadCallback = ((JSAny? _) => _documentLoaded()).toJS;
    frame.addEventListener('load', _loadCallback!);
    _setDocument();
  }

  void _detachDocument() {
    _resizeObserver?.disconnect();
    _resizeObserver = null;
    if (_fontSet != null && _fontCallback != null)
      _fontSet!.removeEventListener('loadingdone', _fontCallback!);
    _fontSet = null;
    _fontCallback = null;
    for (final (element, type, callback) in _imageEvents) {
      element.removeEventListener(type, callback);
    }
    _imageEvents.clear();
  }

  void _setDocument() {
    final frame = _frame;
    if (frame == null) return;
    _detachDocument();
    _generation++;
    _signature = storefrontBannerPresentationSignature(widget.data);
    _style(frame, 'width', '${_width}px');
    _style(frame, 'height', '${_height}px');
    frame.srcdoc = storefrontBannerPreviewDocument(widget.data, _assetBase);
  }

  void _documentLoaded() {
    final doc = _document;
    final root = doc?.querySelector('[data-banner-preview-root]');
    if (!mounted || doc == null || root == null) return;
    _detachDocument();
    final generation = _generation;
    for (final entry in storefrontBannerPreviewColours(widget.data).entries) {
      _style(root, entry.key, entry.value);
    }
    _style(
      root,
      '--font',
      storefrontBannerPreviewFont(widget.data['fontFamily']),
    );
    _setFocal();
    final images = doc.querySelectorAll('img');
    for (var i = 0; i < images.length; i++) {
      final image = images.item(i);
      if (image == null) continue;
      for (final type in ['load', 'error']) {
        final callback = ((JSAny? _) {
          _setFocal();
          _queueMeasure();
        }).toJS;
        image.addEventListener(type, callback);
        _imageEvents.add((image, type, callback));
      }
    }
    // Observers belong to the parent; no executable code enters the sandbox.
    try {
      final callback = ((JSAny? _, JSAny? __) => _queueMeasure()).toJS;
      final observer = BannerPreviewResizeObserver(callback);
      _resizeObserver = observer;
      for (final element in [
        root,
        doc.querySelector('.topScene'),
        doc.querySelector('[data-preview-categories]'),
      ]) {
        if (element != null) observer.observe(element);
      }
    } catch (_) {
      /* Existing browser may lack ResizeObserver; image/font/width events still measure. */
    }
    final fonts = doc.fonts;
    _fontSet = fonts;
    _fontCallback = ((JSAny? _) => _queueMeasure()).toJS;
    fonts.addEventListener('loadingdone', _fontCallback!);
    fonts.ready.toDart.then(
      (_) {
        if (mounted && generation == _generation) _queueMeasure();
      },
      onError: (Object _) {
        if (mounted && generation == _generation) _queueMeasure();
      },
    );
    _queueMeasure();
  }

  void _setFocal() {
    final image = _document?.querySelector('#banner-photo');
    if (image != null)
      _style(
        image,
        'object-position',
        '${widget.focalX.clamp(0, 100)}% ${widget.focalY.clamp(0, 100)}%',
      );
    final banner = _document?.querySelector('[data-sf-menu-banner]');
    if (widget.data['layout'] == 'responsive' && banner != null) {
      final photo = image == null ? null : BannerPreviewImage(image);
      num dimension(String key, int? natural) => natural != null && natural > 0
          ? natural
          : widget.data[key] is num
          ? widget.data[key] as num
          : 0;
      final phone = _width <= 650;
      final height = storefrontResponsiveBannerHeight(
        phone: phone,
        viewportWidth: _width,
        imageWidth: dimension('imageWidth', photo?.naturalWidth),
        imageHeight: dimension('imageHeight', photo?.naturalHeight),
        customHeight: widget.data['heightPx'] is int
            ? widget.data['heightPx'] as int
            : null,
      );
      _style(banner, 'height', '${height}px');
    }
  }

  void _queueMeasure() {
    if (_measureQueued || !mounted) return;
    _measureQueued = true;
    bannerPreviewWindow.requestAnimationFrame(
      ((double _) {
        _measureQueued = false;
        if (mounted) _measure();
      }).toJS,
    );
  }

  void _measure() {
    final doc = _document;
    final root = doc?.querySelector('[data-banner-preview-root]');
    final scene = doc?.querySelector('.topScene');
    if (doc == null ||
        root == null ||
        scene == null ||
        _frame?.isConnected != true)
      return;
    final rect = scene.getBoundingClientRect();
    final categories = doc.querySelector('[data-preview-categories]');
    // scrollHeight has a viewport-height floor and would prevent shrinking.
    final bottom = math.max(
      rect.bottom,
      categories?.getBoundingClientRect().bottom ?? rect.bottom,
    );
    final measured = bottom.ceilToDouble().clamp(1, 6000).toDouble();
    if ((_height - measured).abs() > .5) {
      setState(() => _height = measured);
      _style(_frame!, 'height', '${_height}px');
    }
    final node = doc.querySelector('#banner-photo');
    final photo = node == null ? null : BannerPreviewImage(node);
    final view = photo?.getBoundingClientRect() ?? rect;
    final crop = StorefrontBannerCrop.cover(
      photo?.naturalWidth ?? 0,
      photo?.naturalHeight ?? 0,
      view.width,
      view.height,
      widget.focalX,
      widget.focalY,
      imageLoaded: photo?.complete == true && (photo?.naturalWidth ?? 0) > 0,
      documentHeight: measured,
      contain:
          node != null &&
          bannerPreviewWindow
                  .getComputedStyle(node)
                  .getPropertyValue('object-fit') ==
              'contain',
    );
    if (crop.sameAs(_lastCrop)) return;
    _lastCrop = crop;
    scheduleMicrotask(() {
      if (mounted && identical(_lastCrop, crop)) widget.onCrop(crop);
    });
  }

  @override
  void dispose() {
    _generation++;
    _detachDocument();
    if (_frame != null && _loadCallback != null)
      _frame!.removeEventListener('load', _loadCallback!);
    _frames.remove(_viewId);
    _frame?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final scale = bounds.maxWidth.isFinite
          ? math.min(1.0, bounds.maxWidth / _width)
          : 1.0;
      return ClipRect(
        child: SizedBox(
          width: _width * scale,
          height: _height * scale,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: _width,
            maxWidth: _width,
            minHeight: _height,
            maxHeight: _height,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: _width,
                height: _height,
                child: IgnorePointer(
                  child: HtmlElementView(
                    viewType: _viewType,
                    onPlatformViewCreated: _created,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
