import 'package:flutter/widgets.dart';

bool _defaultOnFilter(int _) => true;

typedef ListItemBuilder = Widget Function(BuildContext context, int index);
typedef FilterCallback = bool Function(int index);

/// A [ListView] with additional utilities surrounding searching: [searching], [onFilter] and [maxLength].
class SearchableListView extends StatelessWidget
// implements ListView
{
  /// If true, enters search mode.
  final bool searching;

  /// The callback used to filter items.
  final FilterCallback onFilter;
  final int itemCount;

  /// The maximum number of items to display when in search mode.
  final int? maxLength;

  final bool reverse;
  final ListItemBuilder itemBuilder;
  final EdgeInsets? padding;

  const SearchableListView.builder({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.searching = false,
    this.onFilter = _defaultOnFilter,
    this.maxLength = 10,
    this.reverse = false,
    this.padding,
  }) : assert(maxLength == null || maxLength >= 0,
            'maxLength cannot be negative.');

  @override
  Widget build(BuildContext context) {
    var itemCount = this.itemCount;
    var itemBuilder = this.itemBuilder;

    if (searching) {
      final indices = <int>[];
      for (var i = 0;
          (maxLength == null || indices.length <= maxLength!) && i < itemCount;
          i++) {
        if (onFilter(i)) indices.add(i);
      }
      itemCount = indices.length;
      itemBuilder =
          (context, index) => this.itemBuilder(context, indices[index]);
    }

    return ListView.builder(
      reverse: reverse,
      padding: padding,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}
