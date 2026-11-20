import 'package:flutter/widgets.dart';

/// A [ListenableBuilder] that skips rebuilds while [select] is unchanged.
///
/// Playback progress ticks five times a second, but a seek bar only looks
/// different once its thumb crosses a pixel and a clock once it reaches a new
/// second. Every rebuild in between would still redraw the whole window on
/// Windows.
class ListenableSelector<T> extends StatefulWidget {
  const ListenableSelector({
    super.key,
    required this.listenable,
    required this.select,
    required this.builder,
  });

  final Listenable listenable;
  final ValueGetter<T> select;
  final WidgetBuilder builder;

  @override
  State<ListenableSelector<T>> createState() => _ListenableSelectorState<T>();
}

class _ListenableSelectorState<T> extends State<ListenableSelector<T>> {
  late T _selected;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(ListenableSelector<T> old) {
    super.didUpdateWidget(old);
    if (old.listenable == widget.listenable) return;
    old.listenable.removeListener(_changed);
    widget.listenable.addListener(_changed);
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (widget.select() != _selected) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _selected = widget.select();
    return widget.builder(context);
  }
}
