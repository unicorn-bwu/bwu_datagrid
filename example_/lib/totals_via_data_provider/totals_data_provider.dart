library bwu_datagrid_examples.totals_data_provider;

import 'package:bwu_utils/bwu_utils_browser.dart' as tools;

import 'package:bwu_datagrid/groupitem_metadata_providers/groupitem_metadata_providers.dart';
import 'package:bwu_datagrid/datagrid/helpers.dart';
import 'package:bwu_datagrid/core/core.dart' as core;

class TotalsDataProvider
    extends MapDataItemProvider<core.ItemBase<dynamic, dynamic>> {
  MapDataItem<dynamic, dynamic> _totals = new MapDataItem<dynamic, dynamic>({});
  List<Column> _columns;

  RowMetadata totalsMetadata = new RowMetadata(
      // Style the totals row differently.
      cssClasses: 'totals',
      columns: new Map<String, Column>());

  TotalsDataProvider(List<MapDataItem<dynamic, dynamic>> data, this._columns)
      : super(data) {
    // Make the totals not editable.
    for (int i = 0; i < _columns.length; i++) {
      totalsMetadata.columns['${i}'] = new Column(editor: null);
    }

    updateTotals();
  }

  @override
  DataItem<dynamic, dynamic> getItem(int index) {
    return (index < items.length) ? items[index] : _totals;
  }

  void updateTotals() {
    int columnIdx = _columns.length;
    while (columnIdx-- > 0) {
      final String columnId = _columns[columnIdx].id;
      int total = 0;
      int i = items.length;
      while (i-- > 0) {
        Object val = items[i][columnId];
        if (val != null) {
          if (val is String) {
            total += (tools.parseInt(items[i][columnId], onErrorDefault: 0));
          } else {
            if (val is int) {
              total += val;
            }
          }
        }
      }
      _totals[columnId] = 'Sum:  ${total}';
    }
  }

  @override
  RowMetadata getItemMetadata(int index) {
    return (index != items.length) ? null : totalsMetadata;
  }

  @override
  int get length => super.length + 1;
}