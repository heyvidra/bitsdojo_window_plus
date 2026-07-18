import 'package:flutter/rendering.dart';

import './window.dart';

class NotImplementedWindow extends DesktopWindow {
  int get handle {
    throw UnimplementedError('handle getter has not been implemented');
  }

  set size(Size newSize) {
    throw UnimplementedError('size setter has not been implemented');
  }

  Size get size {
    throw UnimplementedError('size getter has not been implemented.');
  }

  Rect get rect {
    throw UnimplementedError('rect getter has not been implemented.');
  }

  set rect(Rect newRect) {
    throw UnimplementedError('rect setter has not been implemented.');
  }

  Offset get position {
    throw UnimplementedError('position getter has not been implemented.');
  }

  set position(Offset newPosition) {
    throw UnimplementedError('position setter has not been implemented.');
  }

  set minSize(Size? newSize) {
    throw UnimplementedError('minSize setter has not been implemented.');
  }

  @override
  set maxSize(Size? newSize) {
    throw UnimplementedError('maxSize setter has not been implemented.');
  }

  @override
  Size get screenSize {
    throw UnimplementedError('screenSize getter has not been implemented.');
  }

  @override
  Size get workingScreenSize {
    throw UnimplementedError(
        'workingScreenSize getter has not been implemented.');
  }

  @override
  Rect get workingScreenRect {
    throw UnimplementedError(
        'workingScreenRect getter has not been implemented.');
  }

  Alignment get alignment {
    throw UnimplementedError('alignment getter has not been implemented.');
  }

  set alignment(Alignment? newAlignment) {
    throw UnimplementedError('alignment setter has not been implemented.');
  }

  set title(String newTitle) {
    throw UnimplementedError('title setter has not been implemented.');
  }

  void show() {
    throw UnimplementedError('show() has not been implemented.');
  }

  void hide() {
    throw UnimplementedError('hide() has not been implemented.');
  }

  @override
  bool get isMainWindow => true;

  @Deprecated("use isVisible instead")
  bool get visible {
    return isVisible;
  }

  bool get isVisible {
    throw UnimplementedError('isVisible has not been implemented.');
  }

  @Deprecated("use show()/hide() instead")
  set visible(bool isVisible) {
    throw UnimplementedError('visible setter has not been implemented.');
  }

  @override
  set titleBarHeight(double height) {}

  Size get titleBarButtonSize {
    throw UnimplementedError(
        'titleBarButtonSize getter has not been implemented.');
  }

  double get titleBarHeight {
    throw UnimplementedError('titleBarHeight getter has not been implemented.');
  }

  double get borderSize {
    throw UnimplementedError('borderSize getter has not been implemented.');
  }

  void close() {
    throw UnimplementedError('close() has not been implemented.');
  }

  void minimize() {
    throw UnimplementedError('minimize() has not been implemented.');
  }

  void maximize() {
    throw UnimplementedError('maximize() has not been implemented.');
  }

  void maximizeOrRestore() {
    throw UnimplementedError('maximizeOrRestore has not been implemented.');
  }

  void toggleFullScreen() {
    throw UnimplementedError('toggleFullScreen has not been implemented.');
  }

  void restore() {
    throw UnimplementedError('restore has not been implemented.');
  }

  void startDragging() {
    throw UnimplementedError('startDragging has not been implemented.');
  }

  bool get isMaximized {
    throw UnimplementedError('isMaximized getter has not been implemented.');
  }

  double get scaleFactor {
    throw UnimplementedError('scaleFactor setter has not been implemented');
  }

  bool get alwaysOnTop {
    throw UnimplementedError('isAlwaysOnTop getter has not been implemented');
  }

  set alwaysOnTop(bool onTop) {
    throw UnimplementedError('setAlwaysOnTop setter has not been implemented');
  }

  @override
  bool get hasShadow {
    throw UnimplementedError('hasShadow getter has not been implemented');
  }

  @override
  set hasShadow(bool value) {
    throw UnimplementedError('hasShadow setter has not been implemented');
  }

  @override
  VoidCallback? get onClose => null;

  @override
  set onClose(VoidCallback? callback) {
    throw UnimplementedError('onClose setter has not been implemented');
  }

  @override
  set backgroundEffect(WindowEffect effect) {
    throw UnimplementedError(
        'backgroundEffect setter has not been implemented');
  }

  @override
  int get depth => 0;

  @override
  String? get name => null;

  @override
  Map<String, dynamic>? get arguments => null;

  @override
  Future<void> openNewWindow({
    String? name,
    Size? size,
    Offset? position,
    Map<String, dynamic>? arguments,
  }) {
    throw UnimplementedError('openNewWindow() has not been implemented.');
  }

  @override
  VoidCallback? get onArgumentsChanged => null;

  @override
  set onArgumentsChanged(VoidCallback? callback) {
    throw UnimplementedError(
        'onArgumentsChanged setter has not been implemented');
  }
}
