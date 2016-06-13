@HtmlImport('bwu_datagrid.html')
library bwu_datagrid;

import 'dart:async' show Completer, Future, Stream, StreamSubscription, Timer;
import 'dart:math' as math;
import 'dart:html' as dom;

import 'package:polymer/polymer.dart';
import 'package:web_components/web_components.dart' show HtmlImport;

import 'datagrid/bwu_datagrid_headers.dart';
import 'datagrid/bwu_datagrid_header_column.dart';
import 'datagrid/bwu_datagrid_headerrow_column.dart';

import 'package:bwu_datagrid/plugins/plugin.dart';

import 'package:bwu_datagrid/datagrid/helpers.dart';
import 'package:bwu_datagrid/editors/editors.dart';
import 'package:bwu_datagrid/datagrid/bwu_datagrid_headerrow_column.dart';
import 'package:bwu_datagrid/datagrid/bwu_datagrid_header_column.dart';
import 'package:bwu_datagrid/datagrid/bwu_datagrid_headers.dart';
import 'package:bwu_datagrid/formatters/formatters.dart';
import 'package:bwu_datagrid/groupitem_metadata_providers/groupitem_metadata_providers.dart';

import 'package:bwu_datagrid/core/core.dart' as core;
import 'package:bwu_utils/bwu_utils_browser.dart' as utils;
import 'package:bwu_datagrid/effects/sortable.dart' as sort;
import 'package:bwu_datagrid/effects/dragable.dart' show Dragable;
// ignore: unused_import
import 'package:bwu_datagrid/datagrid/bwu_datagrid_default_theme.dart';
// ignore: unused_import
import 'package:bwu_datagrid/datagrid/bwu_datagrid_style.dart';

@PolymerRegister('bwu-datagrid')
class BwuDatagrid extends PolymerElement {
  BwuDatagrid.created() : super.created();

  bool _isAttached = false;
  bool _isPendingInit = false;

  @override
  void attached() {
    super.attached();
    _isAttached = true;
    if (_isPendingInit) {
      _init();
      render();
      _isPendingInit = false;
      _setupCompleter.complete();
    }

    _eventBus.fire(core.Events.attached, new core.Attached(this));
  }

  static const String defaultThemeName = 'bwu-datagrid-default-theme';

  static const String IGNORE_STYLE_SCOPE = ":not(.style-scope)";

  /// The name of a style module to be used by the datagrids local DOM
  @Property(observer: 'themeChanged')
  String theme = defaultThemeName;

  // DataGrid(dom.Element container, String data, int columns, Options options);
  DataProvider<core.ItemBase> _dataProvider;

  @property
  DataProvider<core.ItemBase> get dataProvider => _dataProvider;

  set data(DataProvider<core.ItemBase> data) {
    setData(data, true);
  }

  List<Column> _columns;

  @property
  List<Column> get columns => _columns;

  GridOptions _gridOptions = new GridOptions();

  @property
  GridOptions get gridOptions => _gridOptions;

  set gridOptions(GridOptions options) {
    setGridOptions = options;
  }

  // settings
  static final Column _columnDefaults = new Column();

  //dom.NodeValidator nodeValidator = new dom.NodeValidatorBuilder.common();

  // scroller
  int _th;

  // virtual height
  double _h;

  // real scrollable height
  double _ph;

  // page height
  int _n;

  // number of pages
  double _cj;

  // "jumpiness" coefficient

  int _page = 0;

  // current page
  int _pageOffset = 0;

  // current page offset
  int _vScrollDir = 1;

  // shared across all grids on the page
  math.Point<int> _scrollbarDimensions;
  int _maxSupportedCssHeight;

  // browser's breaking point

  // private
  bool _initialized = false;

  // ignore: non_constant_identifier_names
  PolymerDom __container;

  PolymerDom get _container {
    if (__container == null) {
      __container = new PolymerDom(root);
    }
    return __container;
  }

  //String uid = "bwu_datagrid_${(1000000 * new math.Random().nextDouble()).round()}";
  dom.Element _focusSink, _focusSink2;
  dom.Element _headerScroller;
  BwuDatagridHeaders _headers;
  dom.Element _headerRow, _headerRowScroller, _headerRowSpacer;
  dom.Element _topPanelScroller;
  dom.Element _topPanel;
  dom.Element _viewport;
  dom.Element _canvas;
  dom.StyleElement _style;
  dom.Element _boundAncestors;
  dom.CssStyleSheet _stylesheet;
  Map<int, dom.CssStyleRule> _columnCssRulesL, _columnCssRulesR;
  int _viewportH = 0;
  int _viewportW = 0;
  int _canvasWidth;
  bool _viewportHasHScroll = false, _viewportHasVScroll = false;
  int _headerColumnWidthDiff = 0,
//      _headerColumnHeightDiff = 0, // border+padding // TODO(zoechi) why is it unused?
      _cellWidthDiff = 0,
      _cellHeightDiff = 0;
  int _absoluteColumnMinWidth;

  int _tabbingDirection = 1;
  int _activePosX;
  int _activeRow, _activeCell;
  dom.Element _activeCellNode;
  Editor _currentEditor;
  dynamic _serializedEditorValue;
  EditController _editController;

  Map<int, RowCache> _rowsCache = <int, RowCache>{};
  int _renderedRows = 0;
  int _numVisibleRows;
  int _prevScrollTop = 0;
  int _scrollTop = 0;

  int _lastRenderedScrollTop = 0;
  int _lastRenderedScrollLeft = 0;
  int _prevScrollLeft = 0;
  int _scrollLeft = 0;

  SelectionModel _selectionModel;
  List<int> _selectedRows = <int>[];

  List<Plugin> _plugins = <Plugin>[];
  Map<String, Map<int, Map<String, String>>> _cellCssClasses =
      <String, Map<int, Map<String, String>>>{};

  Map<String, int> _columnsById = <String, int>{};
  List<SortColumn> _sortColumns = <SortColumn>[];
  List<int> _columnPosLeft = <int>[];
  List<int> _columnPosRight = <int>[];

  // async call handles
  Timer _editorLoaderHandle;
  Timer _renderHandle;
  Timer _postRenderHandle;
  Map<int, List<bool>> _postProcessedRows = <int, List<bool>>{};
  int _postProcessToRow;
  int _postProcessFromRow;

  // perf counters
  int _counterRowsRendered = 0;
  int _counterRowsRemoved = 0;

  // These two variables work around a bug with inertial scrolling in Webkit/Blink on Mac.
  // See http://crbug.com/312427.
  dom.Element _rowNodeFromLastMouseWheelEvent;

  // this node must not be deleted while inertial scrolling
  dom.Element _zombieRowNodeFromLastMouseWheelEvent;

  // node that was hidden instead of getting deleted

  core.EventBus<core.EventData> get eventBus => _eventBus;
  final core.EventBus<core.EventData> _eventBus =
      new core.EventBus<core.EventData>();

  Completer<Null> _setupCompleter;

  @reflectable
  void themeChanged(String newValue, String oldValue) {
    _container
        .querySelectorAll('[bwu-datagrid-theme]')
        .forEach((dom.Element e) => _container.removeChild(e));
    _container.insertBefore(
        new dom.Element.tag('style', 'custom-style')
          ..attributes['bwu-datagrid-theme'] = newValue
          ..attributes['include'] = newValue ?? defaultThemeName,
        $['theme-placeholder']);
    if (_headers != null) {
      _headers.children.forEach((dom.Element header) =>
          (header as BwuDatagridHeaderColumn).set('theme', theme));
    }
    PolymerDom.flush();
    render();
  }

  Future<Null> setup(
      {DataProvider<core.ItemBase> dataProvider,
      List<Column> columns,
      GridOptions gridOptions}) {
    _setupCompleter = new Completer<Null>();
    if (_initialized) {
      if (columns != null) {
        setColumns = columns;
      }
      if (gridOptions != null) {
        setGridOptions = gridOptions;
      }
    } else {
      _dataProvider = dataProvider;
      _columns = columns;
      _gridOptions = gridOptions;
    }

    if (_isAttached) {
      new Future<Null>(() {
        _init();
        render();
        //_unveilElement();
        _setupCompleter.complete();
      });
    } else {
      _isPendingInit = true;
    }
    return _setupCompleter.future;
  }

  //////////////////////////////////////////////////////////////////////////////
  // Initialization

  void init() {
    _finishInitialization();
  }

  void _init() {
    // calculate these only once and share between grid instances
    _maxSupportedCssHeight = _maxSupportedCssHeight != null
        ? _maxSupportedCssHeight
        : _getMaxSupportedCssHeight();
    _scrollbarDimensions = _scrollbarDimensions != null
        ? _scrollbarDimensions
        : _measureScrollbar();

    _validateAndEnforceOptions();
    _columnDefaults.width = _gridOptions.defaultColumnWidth;

    _columnsById = <String, int>{};
    if (columns != null) {
      for (int i = 0; i < columns.length; i++) {
        Column m = new Column()
          ..extend(_columnDefaults)
          ..extend(columns[i]); // TODO extend
        columns[i] = m;
        _columnsById[m.id] = i;
        if (m.minWidth != null && m.width < m.minWidth) {
          m.width = m.minWidth;
        }
        if (m.maxWidth != null && m.width > m.maxWidth) {
          m.width = m.maxWidth;
        }
      }
    }

    _editController =
        new EditController(_commitCurrentEdit, _cancelCurrentEdit);

    this._container.children.clear();
    this
      ..style.overflow = 'hidden'
      ..style.outline = '0'
      ..style.display = 'block' // TODO should be inside the style tag
      //..classes.add(uid)
      ..classes.add("ui-widget");

    // set up a positioning container if needed
    if (!this.style.position.contains(new RegExp('relative|absolute|fixed'))) {
      this.style.position = 'relative';
    }

    _focusSink = ($['focusSink'] as dom.DivElement)
      ..style.position = 'fixed'
      ..style.width = '0'
      ..style.height = '0'
      ..style.top = '0'
      ..style.left = '0'
      ..style.outline = '0';

    _headerScroller = ($['headerScroller'] as dom.DivElement)
      //..classes.add('bwu-datagrid-header')
      //..classes.add('ui-state-default')
      ..style.overflow = 'hidden'
      ..style.position = 'relative';
    //_container.append(_headerScroller);

    _headers = ($['bwuDatagridHeaders']
        as BwuDatagridHeaders) //(new dom.Element.tag('bwu-datagrid-headers') as BwuDatagridHeaders)
      //..classes.add('bwu-datagrid-header-columns')
      ..style.left = '-1000px';
    //_headerScroller.append(_headers);
    _headers.style.width = "${_getHeadersWidth()}px";

    _headerRowScroller = ($['headerRowScroller'] as dom.DivElement)
//      ..classes.add('bwu-datagrid-headerrow')
//      ..classes.add('ui-state-default')
      ..style.overflow = 'hidden'
      ..style.position = 'relative';
    //_container.append(_headerRowScroller);

    _headerRow = $['headerRow']; //new dom.DivElement()
    //..classes.add('bwu-datagrid-headerrow-columns');
    //_headerRowScroller.append(_headerRow);

    _headerRowSpacer = ($['spacer'] as dom.DivElement)
      ..style.display = 'block'
      ..style.height = '1px'
      ..style.position = 'absolute'
      ..style.top = '0'
      ..style.left = '0'
      ..style.width = '${_getCanvasWidth() + _scrollbarDimensions.x}px';
    //_headerRowScroller.append(_headerRowSpacer);

    _topPanelScroller = ($['topPanelScroller'] as dom.DivElement)
      //..classes.add('bwu-datagrid-top-panel-scroller')
      //..classes.add('ui-state-default')
      ..style.overflow = 'hidden'
      ..style.position = 'relative';
    //_container.append(_topPanelScroller);
    _topPanel = ($['topPanel'] as dom.DivElement)
      //..classes.add('bwu-datagrid-top-panel')
      ..style.width = '10000px';
    //_topPanelScroller.append(_topPanel);

    if (!_gridOptions.showTopPanel) {
      _topPanelScroller.style.display = 'none'; //hide();
    }

    if (!_gridOptions.showHeaderRow) {
      _headerRowScroller.style.display = 'none'; // hide();
    }

    _viewport = ($['viewport'] as dom.DivElement)
      //..classes.add('bwu-datagrid-viewport')
      ..style.width = '100%'
      ..style.overflow = 'auto'
      ..style.outline = '0'
      ..style.position = 'relative';
    //_container.append(_viewport);
    _viewport.style.overflowY = _gridOptions.autoHeight ? "hidden" : "auto";

    _canvas = $['canvas']; //new dom.DivElement()..classes.add('grid-canvas');
    //_viewport.append(_canvas);

    _focusSink2 = (_focusSink.clone(true) as dom.DivElement)..id = 'focusSink2';
    _container.append(_focusSink2);

    if (!_gridOptions.explicitInitialization) {
      _finishInitialization();
    }
  }

  void _finishInitialization() {
    if (!_initialized) {
      _initialized = true;

      _viewportW = this
          .clientWidth
          .round(); //tools.parseInt(this.getComputedStyle().width);

      // header columns and cells may have different padding/border skewing width calculations (box-sizing, hello?)
      // calculate the diff so we can set consistent sizes
      _measureCellPaddingAndBorder();

      // for usability reasons, all text selection in BwuDatagrid is disabled
      // with the exception of input and textarea elements (selection must
      // be enabled there so that editors work as expected); note that
      // selection in grid cells (grid body) is already unavailable in
      // all browsers except IE
      _disableSelection(
          _headers); // disable all text selection in header (including input and textarea)

      if (!_gridOptions.enableTextSelectionOnCells) {
        // disable text selection in grid cells except in input and textarea elements
        // (this is IE-specific, because selectstart event will only fire in IE)
        _viewport.onSelectStart.listen((dom.Event event) {
          //  bind("selectstart.ui",
          if (!(event.target is dom.InputElement ||
              event.target is dom.TextAreaElement)) {
            event.preventDefault();
          }
        });
      }

      _updateColumnCaches();
      _createColumnHeaders();
      _setupColumnSort();
      _createCssRules();
      resizeCanvas();
      _bindAncestorScrollEvents();

      _container.node.on['resize']
          .listen(resizeCanvas); // TODO resize isn't fired by default
      //$viewport
      //.bind("click", handleClick)
      _viewport.onScroll.listen(_handleScroll);
      _headerScroller
        ..onContextMenu.listen(_handleHeaderContextMenu)
        ..onClick.listen(_handleHeaderClick)
        ..querySelectorAll(".bwu-datagrid-header-column${IGNORE_STYLE_SCOPE}")
            .forEach((dom.Element e) {
          e
            ..onMouseEnter.listen(_handleHeaderMouseEnter)
            ..onMouseLeave.listen(_handleHeaderMouseLeave);
        });
      _headerRowScroller.onScroll.listen(_handleHeaderRowScroll);
      _focusSink.onKeyDown.listen(_handleKeyDown);
      //..append(_focusSink2);
      _focusSink2.onKeyDown.listen(_handleKeyDown);
      _canvas
        ..onKeyDown.listen(_handleKeyDown)
        ..onClick.listen(_handleClick)
        ..onDoubleClick.listen(_handleDblClick)
        ..onContextMenu.listen(_handleContextMenu)
        ..onDrag.listen(_handleDrag)
        ..onDragStart.listen(_handleDragStart)
        ..onDragEnd.listen(_handleDragEnd)
        ..onDragEnter.listen(_handleDragEnter)
        ..onDragLeave.listen(_handleDragLeave)
        ..onDragOver.listen(_handleDragOver)
        ..onDrop.listen(_handleDrop);

//      _canvasDrag = new cdrag.DragAware(_canvas, distance: 3)
//          ..onBwuCustomDrag.listen(_handleCustomDrag)
//          ..onBwuCustomDragStart.listen(_handleCustomDragStart)
//          ..onBwuCustomDragEnd.listen(_handleCustomDragEnd);
//          ..querySelectorAll(".bwu-datagrid-cell").forEach((e) {
//            (e as dom.Element)
//              ..onMouseEnter.listen(handleMouseEnter)
//              ..onMouseLeave.listen(handleMouseLeave);
//          });

      // TODO does Dart need this?
      // Work around http://crbug.com/312427.
      if (dom.window.navigator.userAgent.toLowerCase().contains('webkit') &&
          dom.window.navigator.userAgent.toLowerCase().contains('macintosh')) {
        _canvas.onMouseWheel.listen(_handleMouseWheel);
      }
    }
  }

  Map<Plugin, List<Plugin>> _suspendedPlugins = <Plugin, List<Plugin>>{};

  void registerPlugin(Plugin plugin, {bool suspendOthers: false}) {
    if (suspendOthers) {
      _suspendedPlugins[plugin] = <Plugin>[];
      _plugins.forEach((Plugin p) {
        if (p.runtimeType == plugin.runtimeType && !p.isSuspended) {
          _suspendedPlugins[plugin].add(p);
          p.isSuspended = true;
        }
      });
    }
    _plugins.insert(0, plugin);
    plugin.init(this);
  }

  void unregisterPlugin(Plugin plugin) {
    for (int i = 0; i < _plugins.length; i++) {
      if (_plugins[i] == plugin) {
        _plugins[i].destroy();
        _plugins.removeAt(i);
        break;
      }
    }
    if (_suspendedPlugins.containsKey(plugin)) {
      _suspendedPlugins[plugin].forEach((Plugin p) {
        p.isSuspended = false;
      });
      _suspendedPlugins.remove(plugin);
    }
  }

  StreamSubscription<core.SelectedRangesChanged> _onSelectedRangesChanged;

  set setSelectionModel(SelectionModel model) {
    if (_selectionModel != null) {
      if (_onSelectedRangesChanged != null) {
        _onSelectedRangesChanged
            .cancel(); //selectionModel.onSelectedRangesChanged.unsubscribe(handleSelectedRangesChanged);
      }
      _selectionModel.destroy();
    }

    _selectionModel = model;
    if (_selectionModel != null) {
      _selectionModel.init(this);
      _onSelectedRangesChanged =
          onBwuSelectedRangesChanged.listen(_selectedRangesChangedHandler);
    }
  }

  SelectionModel get getSelectionModel => _selectionModel;

  dom.Element get getCanvasNode => _canvas;

  math.Point<int> _measureScrollbar() {
    final dom.Element c = new dom.DivElement()
      ..style.position = 'absolute'
      ..style.top = '-10000px'
      ..style.left = '10000px'
      ..style.width = '100px'
      ..style.height = '100px'
      ..style.overflow = 'scroll';
    dom.document.body.append(c);
    final math.Point<int> dim = new math.Point<int>(
        c.offsetWidth.round() - c.clientWidth.round(),
        c.offsetHeight.round() - c.clientHeight.round());
    c.remove();
    return dim;
  }

  int _getHeadersWidth() {
    int headersWidth = 0;
    int ii = columns != null ? columns.length : 0;
    for (int i = 0; i < ii; i++) {
      int width = columns[i].width;
      headersWidth += width;
    }
    headersWidth += _scrollbarDimensions.x;
    return math.max(headersWidth, _viewportW).round() + 1000;
  }

  int _getCanvasWidth() {
    int availableWidth = _viewportHasVScroll
        ? _viewportW - _scrollbarDimensions.x.round()
        : _viewportW;
    int rowWidth = 0;
    int i = columns != null ? columns.length : 0;
    while (i-- > 0) {
      rowWidth += columns[i].width;
    }
    return _gridOptions.fullWidthRows
        ? math.max(rowWidth, availableWidth)
        : rowWidth;
  }

  void _updateCanvasWidth([bool forceColumnWidthsUpdate]) {
    int oldCanvasWidth = _canvasWidth;
    _canvasWidth = _getCanvasWidth();

    if (_canvasWidth != oldCanvasWidth) {
      _canvas.style.width = "${_canvasWidth}px";
      _headerRow.style.width = "${_canvasWidth}px";
      _headers.style.width = "${_getHeadersWidth()}px";
      _viewportHasHScroll =
          (_canvasWidth > _viewportW - _scrollbarDimensions.x);
    }

    _headerRowSpacer.style.width =
        "${(_canvasWidth + (_viewportHasVScroll ? _scrollbarDimensions.x : 0))}px";

    if (_canvasWidth != oldCanvasWidth || forceColumnWidthsUpdate) {
      _applyColumnWidths();
    }
  }

  void _disableSelection(dom.Element target) {
// TODO also for all childs ?? commented out lines below didn't change anything
// starting in the text of a header and dragging down to the grid selects text
    if (target != null) {
      target
        ..attributes['unselectable'] = 'on'
        ..style.userSelect = 'none'
        ..onSelectStart.listen((dom.Event e) {
          e..preventDefault();
          //..stopPropagation()
          //..stopImmediatePropagation();
        }); // bind("selectstart.ui", function () {
    }
    target.querySelectorAll('*').forEach((dom.Element e) {
      e..attributes['unselectable'] = 'on';
//        ..style.userSelect= 'none'
//        ..onSelectStart.listen((e) {
//          e
//            ..preventDefault()
//            ..stopPropagation()
//            ..stopImmediatePropagation();
//      });
    });
  }

  int _getMaxSupportedCssHeight() {
    int supportedHeight = 1000000;
    // FF reports the height back but still renders blank after ~6M px
    int testUpTo = dom.window.navigator.userAgent
        .toLowerCase()
        .contains('firefox') ? 6000000 : 1000000000; // TODO check match
    final dom.DivElement div = new dom.DivElement()..style.display = 'none';
    dom.document.body.append(div);

    while (true) {
      int test = supportedHeight * 2;
      div.style.height = "${test}px";
      if (test > testUpTo || div.getComputedStyle().height != "${test}px") {
        break;
      } else {
        supportedHeight = test;
      }
    }

    div.remove();
    return supportedHeight;
  }

  final List<StreamSubscription<dom.Event>> _scrollSubscription =
      <StreamSubscription<dom.Event>>[];

  // TODO:  this is static.  need to handle page mutation.
  void _bindAncestorScrollEvents() {
    dom.Element elem = _canvas;

    if (elem.parentNode is dom.ShadowRoot) {
      elem = (elem.parentNode as dom.ShadowRoot).host;
    } else {
      elem = elem.parent;
    }

    while (elem != this && elem != null) {
      // bind to scroll containers only
      if (elem == _viewport ||
          elem.scrollWidth != elem.clientWidth ||
          elem.scrollHeight != elem.clientHeight) {
        if (_boundAncestors == null) {
          _boundAncestors = elem;
        } else {
          try {
            _boundAncestors.append(elem);
          } catch (e) {
            print(e);
          }
        }
        _scrollSubscription
            .add(elem.onScroll.listen(_handleActiveCellPositionChange));
      }
      if (elem.parentNode is dom.ShadowRoot) {
        elem = (elem.parentNode as dom.ShadowRoot).host;
      } else {
        elem = elem.parent;
      }
    }
  }

  void _unbindAncestorScrollEvents() {
    if (_boundAncestors == null) {
      return;
    }
    _scrollSubscription
        .forEach((StreamSubscription<dom.Event> e) => e.cancel());
    _scrollSubscription.clear();
    //$boundAncestors.unbind("scroll." + uid);
    _boundAncestors = null;
  }

  void updateColumnHeader(String columnId, String title, String toolTip,
      {dom.Element nameElement}) {
    if (!_initialized) {
      return;
    }
    final int idx = getColumnIndex(columnId);
    if (idx == null) {
      return;
    }

    Column columnDef = columns[idx];
    dom.Element header = _headers.children[idx];
    if (header != null) {
      if (title != null) {
        columns[idx].name = title;
      }
      if (nameElement != null) {
        columns[idx].nameElement = nameElement;
      }
      if (toolTip != null) {
        columns[idx].toolTip = toolTip;
      }

      _eventBus.fire(core.Events.beforeHeaderCellDestroy,
          new core.BeforeHeaderCellDestroy(this, header, columnDef));

      header..attributes["title"] = toolTip != null ? toolTip : "";
      if (nameElement == null && title != null) {
        header.text = title;
      }
      if (nameElement != null) {
        header.children.clear();
        header.append(nameElement);
      }

      _eventBus.fire(core.Events.headerCellRendered,
          new core.HeaderCellRendered(this, header, columnDef));
    }
  }

  dom.Element getHeaderRow() {
    return _headerRow;
  }

  dom.Element getHeaderRowColumn(Object columnId) {
    final int idx = getColumnIndex(columnId);
    dom.Element header = _headerRow.children
        .firstWhere((dom.Element e) => _headerRow.children.indexOf(e) == idx);
    if (header != null && header.children.length > 0) {
      return header;
    }
    return null;
  }

  void _createColumnHeaders() {
    void onMouseEnter(dom.MouseEvent e) {
      (e.target as dom.Element).classes.add("ui-state-hover");
    }

    void onMouseLeave(dom.MouseEvent e) {
      (e.target as dom.Element).classes.remove("ui-state-hover");
    }

    _headers
        .querySelectorAll(".bwu-datagrid-header-column${IGNORE_STYLE_SCOPE}")
        .forEach((dom.Element e) {
      // TODO check self/this
      Column columnDef = (e as BwuDatagridHeaderColumn).column;
      if (columnDef != null) {
        _eventBus.fire(core.Events.beforeHeaderCellDestroy,
            new core.BeforeHeaderCellDestroy(this, e, columnDef));
      }
    });
    _headers.children.clear();
    _headers.style.width = "${_getHeadersWidth()}px";

    _headerRow
        .querySelectorAll(".bwu-datagrid-headerrow-column${IGNORE_STYLE_SCOPE}")
        .forEach((dom.Element e) {
      // TODO check self/this
      Column columnDef = (e as BwuDatagridHeaderrowColumn).column;
      if (columnDef != null) {
        _eventBus.fire(core.Events.beforeHeaderCellDestroy,
            new core.BeforeHeaderCellDestroy(this, e, columnDef));
      }
    });
    _headerRow.children.clear();

    if (columns != null) {
      for (int i = 0; i < columns.length; i++) {
        Column m = columns[i];

        dom.Node nameElement;
        if (m.nameElement == null && m.name.isNotEmpty) {
          nameElement = new dom.SpanElement()
            ..classes.add('bwu-datagrid-column-name')
            ..text = m
                .name; // TODO this span element is not added in updateColumnHeader()
        }
        if (m.nameElement != null) {
          nameElement = m.nameElement;
        }
        if (nameElement == null) {
          nameElement = new dom.Text('');
        }
        final BwuDatagridHeaderColumn header = new BwuDatagridHeaderColumn()
          ..classes.add('ui-state-default')
          ..classes.add('bwu-datagrid-header-column')
          ..append(nameElement)
          ..style.width = "${m.width - _headerColumnWidthDiff}px"
          //..attributes["id"] ='${uid}${m.id}'
          ..attributes["id"] = '${m.id}'
          ..attributes["title"] = m.toolTip != null ? m.toolTip : ""
          ..attributes['ismovable'] = '${m.isMovable}'
          ..column = m;
        if (m.headerCssClass != null) {
          header.classes.add(m.headerCssClass);
        }
        _headers.append(header);
        _headers.set('theme', theme);

        if (_gridOptions.enableColumnReorder || m.sortable) {
          header
            ..onMouseEnter.listen(onMouseEnter)
            ..onMouseLeave.listen(onMouseLeave);
        }

        if (m.sortable) {
          header.classes.add("bwu-datagrid-header-sortable");
          header.append(new dom.SpanElement()
            ..classes.add('bwu-datagrid-sort-indicator'));
        }

        _eventBus.fire(core.Events.headerCellRendered,
            new core.HeaderCellRendered(this, header, m));

        if (_gridOptions.showHeaderRow) {
          final dom.Element headerRowCell =
              (new dom.Element.tag('bwu-datagrid-headerrow-column')
                  as BwuDatagridHeaderrowColumn)
                ..classes.add('ui-state-default')
                ..classes.add('bwu-datagrid-headerrow-column')
                ..classes.add('l${i}')
                ..classes.add('r${i}')
                ..column = m;
          _headerRow.append(headerRowCell);

          _eventBus.fire(core.Events.headerRowCellRendered,
              new core.HeaderRowCellRendered(this, headerRowCell, m));
        }
      }
    }

    setSortColumns(_sortColumns);
    _setupColumnResize();
    if (_gridOptions.enableColumnReorder) {
      _setupColumnReorder();
    }
  }

  void _setupColumnSort() {
    _headers.onClick.listen((dom.MouseEvent e) {
      // temporary workaround for a bug in jQuery 1.7.1 (http://bugs.jquery.com/ticket/11328)
      // e.metaKey = e.metaKey || e.ctrlKey; // TODO process Ctrl-key

      if ((e.target as dom.Element)
          .classes
          .contains("bwu-datagrid-resizable-handle")) {
        return;
      }

      final BwuDatagridHeaderColumn col = tw_bwu_closest(
              (e.target as dom.Element), '.bwu-datagrid-header-column')
          as BwuDatagridHeaderColumn;
      if (col.children.length == 0) {
        return;
      }

      Column column = col.column;
      if (column.sortable) {
        if (!getEditorLock.commitCurrentEdit()) {
          return;
        }

        SortColumn sortOpts;
        int i = 0;
        for (; i < _sortColumns.length; i++) {
          if (_sortColumns[i].columnId == column.id) {
            sortOpts = _sortColumns[i];
            sortOpts.sortAsc = !sortOpts.sortAsc;
            break;
          }
        }

        if (e.metaKey && _gridOptions.multiColumnSort) {
          if (sortOpts != null) {
            _sortColumns.removeAt(i);
          }
        } else {
          if ((!e.shiftKey && !e.metaKey) || !_gridOptions.multiColumnSort) {
            _sortColumns = <SortColumn>[];
          }

          if (sortOpts == null) {
            sortOpts = new SortColumn(column.id, column.defaultSortAsc);
            _sortColumns.add(sortOpts);
          } else if (_sortColumns.length == 0) {
            _sortColumns.add(sortOpts);
          }
        }

        setSortColumns(_sortColumns);

        if (!_gridOptions.multiColumnSort) {
          _eventBus.fire(core.Events.sort,
              new core.Sort(this, false, column, null, sortOpts.sortAsc, e));
        } else {
          final Map<Column, bool> sortCols = new Map<Column, bool>.fromIterable(
              _sortColumns,
              key: (SortColumn k) => columns[getColumnIndex(k.columnId)],
              value: (SortColumn k) => k.sortAsc);
          _eventBus.fire(core.Events.sort,
              new core.Sort(this, true, null, sortCols, null, e));
        }
      }
    });
  }

  void _setupColumnReorder() {
    //_headers.filter = new sort.Filter(":ui-sortable")
    if (_headers.sortable != null) {
      _headers.sortable.destroy();
    }
    _headers.sortable = new sort.Sortable(
        sortable: _headers,
        //selector: 'ui-sortable',
        containment: 'parent',
        distance: 3,
        axis: sort.ReorderAxis.horizontal,
        cursor: 'default',
        // tolerance: 'intersection',
        // helper: 'clone',
        placeholderCssClass:
            'bwu-datagrid-sortable-placeholder ui-state-default bwu-datagrid-header-column',
        start: (dom.Element elm, dom.Element helper, dom.Element placeholder) {
          //placeholder.style.width = '${tools.outerWidth(elm) - _headerColumnWidthDiff}px';
          helper.classes.add('bwu-datagrid-header-column-active');
        },
        beforeStop: (dom.Element elm, dom.Element helper) {
          helper.classes.remove('bwu-datagrid-header-column-active');
          if (!getEditorLock.commitCurrentEdit()) {
            _headers.sortable.cancel();
          }
        });
    _headers.sortable.stop = (dom.Event e) {
      final List<Object> reorderedIds =
          _headers.sortable.reorderedIds; //("toArray");
      final List<Column> reorderedColumns = <Column>[];
      for (int i = 0; i < reorderedIds.length; i++) {
        reorderedColumns.add(columns[getColumnIndex(reorderedIds[i])]);
      }
      setColumns = reorderedColumns;

      _eventBus.fire(
          core.Events.columnsReordered, new core.ColumnsReordered(this));
      e.stopPropagation();
      _setupColumnResize();
    };
  }

  void _setupColumnResize() {
    Column c;
    int pageX;
    List<BwuDatagridHeaderColumn> columnElements;
    int minPageX, maxPageX;
    int firstResizable, lastResizable;
    columnElements = new List<BwuDatagridHeaderColumn>.from(_headers.children);
    _headers
        .querySelectorAll(".bwu-datagrid-resizable-handle")
        .forEach((dom.Element e) {
      e.remove();
    });
    for (int i = 0; i < columnElements.length; i++) {
      if (columns[i].resizable) {
        if (firstResizable == null) {
          firstResizable = i;
        }
        lastResizable = i;
      }
    }
    if (firstResizable == null) {
      return;
    }
    for (int i = 0; i < columnElements.length; i++) {
      final BwuDatagridHeaderColumn headerCol = columnElements[i];
      if (i < firstResizable ||
          (_gridOptions.forceFitColumns && i >= lastResizable)) {
        continue;
      }

      final dom.DivElement div = new dom.DivElement()
        ..classes.add('bwu-datagrid-resizable-handle')
        //`..draggable = true` breaks custom drag-and-drop in Chrome
        ..attributes['nonsortable'] = 'true'
        ..attributes['bwu-draggable'] = 'true';
      headerCol.append(div);

      new Dragable(div)
        ..onDragStart.listen((dom.MouseEvent e) {
          if (!getEditorLock.commitCurrentEdit()) {
            e.preventDefault; // TODO(zoechi) is this the proper translation from `return false;`?
            return; // false;
          }
          pageX = e.page.x;
          (e.target as dom.Element)
              .parent
              .classes
              .add("bwu-datagrid-header-column-active");
          int shrinkLeewayOnRight;
          int stretchLeewayOnRight;
          // lock each column's width option to current width
          for (int i = 0; i < columnElements.length; i++) {
            columns[i].previousWidth = utils.outerWidth(columnElements[i]);
          }
          if (_gridOptions.forceFitColumns) {
            shrinkLeewayOnRight = 0;
            stretchLeewayOnRight = 0;
            // colums on right affect maxPageX/minPageX
            for (int j = i + 1; j < columnElements.length; j++) {
              c = columns[j];
              if (c.resizable) {
                if (stretchLeewayOnRight != null) {
                  if (c.maxWidth != null) {
                    stretchLeewayOnRight += c.maxWidth - c.previousWidth;
                  } else {
                    stretchLeewayOnRight = null;
                  }
                }
                shrinkLeewayOnRight += c.previousWidth -
                    math.max(c.minWidth != null ? c.minWidth : 0,
                        _absoluteColumnMinWidth);
              }
            }
          }
          int shrinkLeewayOnLeft = 0, stretchLeewayOnLeft = 0;
          for (int j = 0; j <= i; j++) {
            // columns on left only affect minPageX
            c = columns[j];
            if (c.resizable) {
              if (stretchLeewayOnLeft != null) {
                if (c.maxWidth != null) {
                  stretchLeewayOnLeft += c.maxWidth - c.previousWidth;
                } else {
                  stretchLeewayOnLeft = null;
                }
              }
              shrinkLeewayOnLeft += c.previousWidth -
                  math.max/*<int>*/(c.minWidth != null ? c.minWidth : 0,
                      _absoluteColumnMinWidth);
            }
          }
          if (shrinkLeewayOnRight == null) {
            shrinkLeewayOnRight = 100000;
          }
          if (shrinkLeewayOnLeft == null) {
            shrinkLeewayOnLeft = 100000;
          }
          if (stretchLeewayOnRight == null) {
            stretchLeewayOnRight = 100000;
          }
          if (stretchLeewayOnLeft == null) {
            stretchLeewayOnLeft = 100000;
          }
          maxPageX = pageX +
              math.min/*<int>*/(shrinkLeewayOnRight, stretchLeewayOnLeft);
          minPageX = pageX -
              math.min/*<int>*/(shrinkLeewayOnLeft, stretchLeewayOnRight);
        })
        ..onDrag.listen((dom.MouseEvent e) {
          int actualMinWidth;
          if (e.page.x == 0) {
            return;
          }
          int d = math.min(maxPageX, math.max(minPageX, e.page.x)) - pageX;

          int x;
          if (d < 0) {
            // shrink column
            x = d;
            for (int j = i; j >= 0; j--) {
              c = columns[j];
              if (c.resizable) {
                actualMinWidth = math.max(c.minWidth != null ? c.minWidth : 0,
                    _absoluteColumnMinWidth);
                if (x != 0 && c.previousWidth + x < actualMinWidth) {
                  x += c.previousWidth - actualMinWidth;
                  c.width = actualMinWidth;
                } else {
                  c.width = c.previousWidth + x;
                  x = 0;
                }
              }
            }

            if (_gridOptions.forceFitColumns) {
              x = -d;
              for (int j = i + 1; j < columnElements.length; j++) {
                c = columns[j];
                if (c.resizable) {
                  if (x != 0 &&
                      c.maxWidth != null &&
                      (c.maxWidth - c.previousWidth < x)) {
                    x -= c.maxWidth - c.previousWidth;
                    c.width = c.maxWidth;
                  } else {
                    c.width = c.previousWidth + x;
                    x = 0;
                  }
                }
              }
            }
          } else {
            // stretch column
            x = d;
            for (int j = i; j >= 0; j--) {
              c = columns[j];
              if (c.resizable) {
                if (x != 0 &&
                    c.maxWidth != null &&
                    (c.maxWidth - c.previousWidth < x)) {
                  x -= c.maxWidth - c.previousWidth;
                  c.width = c.maxWidth;
                } else {
                  c.width = c.previousWidth + x;
                  x = 0;
                }
              }
            }

            if (_gridOptions.forceFitColumns) {
              x = -d;
              for (int j = i + 1; j < columnElements.length; j++) {
                c = columns[j];
                if (c.resizable) {
                  actualMinWidth = math.max(c.minWidth != null ? c.minWidth : 0,
                      _absoluteColumnMinWidth);
                  if (x != 0 && c.previousWidth + x < actualMinWidth) {
                    x += c.previousWidth - actualMinWidth;
                    c.width = actualMinWidth;
                  } else {
                    c.width = c.previousWidth + x;
                    x = 0;
                  }
                }
              }
            }
          }
          _applyColumnHeaderWidths();
          if (_gridOptions.syncColumnCellResize) {
            new Future<Null>(_applyColumnWidths);
          }
        })
        ..onDragEnd.listen((dom.MouseEvent e) {
          int newWidth;
          (e.target as dom.Element)
              .parent
              .classes
              .remove("bwu-datagrid-header-column-active");
          for (int j = 0; j < columnElements.length; j++) {
            c = columns[j];
            newWidth = utils.outerWidth(columnElements[j]);

            if (c.previousWidth != newWidth && c.rerenderOnResize) {
              invalidateAllRows();
            }
          }
          _updateCanvasWidth(true);
          render();
          _eventBus.fire(
              core.Events.columnsResized, new core.ColumnsResized(this));
        });
    }
  }

  int _getVBoxDelta(dom.Element el) {
//    var p = [ // TODO(zoechi) why is it unused?
//      "borderTopWidth",
//      "borderBottomWidth",
//      "paddingTop",
//      "paddingBottom"
//    ];
    int delta = 0;
    final dom.CssStyleDeclaration gcs = el.getComputedStyle();
    delta += utils.parseIntDropUnit(gcs.borderTopWidth) +
        utils.parseIntDropUnit(gcs.borderBottomWidth) +
        utils.parseIntDropUnit(gcs.paddingTop) +
        utils.parseIntDropUnit(gcs.paddingBottom);

//    p.forEach((prop) {
//      delta += tools.parseInt($el.style.getPropertyValue(prop)); // || 0; // TODO
//    });
    return delta;
  }

  void _measureCellPaddingAndBorder() {
    dom.Element el;
    // changed to direct property access due to https://code.google.com/p/dart/issues/detail?id=18765
//    var h = ["borderLeftWidth", "borderRightWidth", "paddingLeft", "paddingRight"];
//    var v = ["borderTopWidth", "borderBottomWidth", "paddingTop", "paddingBottom"];

    el = (new dom.Element.tag('bwu-datagrid-header-column')
        as BwuDatagridHeaderColumn)
      ..classes.add('ui-state-default')
      ..classes.add('bwu-datagrid-header-column')
      ..style.visibility = 'hidden';
    _headers.append(el);
    _headerColumnWidthDiff =
        /*_headerColumnHeightDiff = TODO(zoechi) why isn't it used? */ 0;
    dom.CssStyleDeclaration gcs = el.getComputedStyle();
    if (el.style.boxSizing != "border-box") {
      //h.forEach((prop) {
      _headerColumnWidthDiff = utils.parseIntDropUnit(gcs.borderLeftWidth) +
          utils.parseIntDropUnit(gcs.borderRightWidth) +
          utils.parseIntDropUnit(gcs.paddingLeft) +
          utils.parseIntDropUnit(gcs.paddingRight);
      // || 0; // TODO
      //});
      //v.forEach((prop) {
      //  headerColumnHeightDiff += tools.parseInt(gcs.getPropertyValue(prop)); //; || 0; // TODO
      //});
//      _headerColumnHeightDiff = utils.parseIntDropUnit(gcs.borderTopWidth) + // TODO(zoechi) why is it unused?
//          utils.parseIntDropUnit(gcs.borderBottomWidth) +
//          utils.parseIntDropUnit(gcs.paddingTop) +
//          utils.parseIntDropUnit(gcs.paddingBottom);
    }
    el.remove();

    final dom.DivElement r = new dom.DivElement()
      ..classes.add('bwu-datagrid-row');
    _canvas.append(r);
    el = new dom.DivElement()
      ..id = ''
      ..classes.add('bwu-datagrid-cell')
      ..style.visibility = 'hidden'
      ..appendText('-');

    r.append(el);
    gcs = el.getComputedStyle();
    _cellWidthDiff = _cellHeightDiff = 0;
    if (el.style.boxSizing != "border-box") {
//      h.forEach((prop) {
//        var val = tools.parseInt(el.getComputedStyle().getPropertyValue(prop));
//        cellWidthDiff += val != null ? val : 0; // TODO
//      });
      _cellWidthDiff = utils.parseIntDropUnit(gcs.borderLeftWidth) +
          utils.parseIntDropUnit(gcs.borderRightWidth) +
          utils.parseIntDropUnit(gcs.paddingLeft) +
          utils.parseIntDropUnit(gcs.paddingRight);
//      v.forEach((prop) {
//        var val = tools.parseInt(el.getComputedStyle().getPropertyValue(prop));
//        cellHeightDiff += val != null ? val : 0; // TODO
//      });
      _cellHeightDiff = utils.parseIntDropUnit(gcs.borderTopWidth) +
          utils.parseIntDropUnit(gcs.borderBottomWidth) +
          utils.parseIntDropUnit(gcs.paddingTop) +
          utils.parseIntDropUnit(gcs.paddingBottom);
    }
    //var x = r.getComputedStyle();
    r.remove();

    _absoluteColumnMinWidth = math.max(_headerColumnWidthDiff, _cellWidthDiff);
  }

  void _createCssRules() {
    _style = new dom.StyleElement();
    _container.append(_style);
    final int rowHeight = (_gridOptions.rowHeight - _cellHeightDiff);
    final List<String> rules = <String>[
      ".bwu-datagrid-header-column { left: 1000px; }",
      ".bwu-datagrid-top-panel { height:${_gridOptions.topPanelHeight}px; }",
      ".bwu-datagrid-headerrow-columns { height:${_gridOptions
          .headerRowHeight}px; }",
      ".bwu-datagrid-cell { height:${rowHeight}px; }",
      ".bwu-datagrid-row { height:${_gridOptions.rowHeight}px; }"
    ];

    if (columns != null) {
      for (int i = 0; i < columns.length; i++) {
        rules.add(".l${i} { }");
        rules.add(".r${i} { }");
      }
    }

//    for(int i = 0; i < rules.length; i++) {
//      ($style.sheet as dom.CssStyleSheet).insertRule(rules[i], i);
//    }
    _style.appendText(rules.join(" "));
  }

  Map<String, dom.CssStyleRule> _getColumnCssRules(int idx) {
    if (_stylesheet == null) {
      _stylesheet = _style.sheet;

      // find and cache column CSS rules
      _columnCssRulesL = <int, dom.CssStyleRule>{};
      _columnCssRulesR = <int, dom.CssStyleRule>{};
      final List<dom.CssRule> cssRules = _stylesheet.cssRules;
      Match matches;
      int columnIdx;
      for (int i = 0; i < cssRules.length; i++) {
        final String selector = cssRules[i].cssText; //selectorText;
        matches = new RegExp(r'(?:\.l)(\d+)').firstMatch(selector);
        if (matches != null) {
          columnIdx = utils.parseInt(
              matches.group(1)); // first.substr(2, matches.first.length - 2));
          _columnCssRulesL[columnIdx] = cssRules[i];
        } else {
          matches = new RegExp(r'(?:\.r)(\d+)').firstMatch(selector);
          if (matches != null) {
            columnIdx = utils.parseInt(
                matches.group(1)); //first.substr(2, matches.first.length - 2));
            _columnCssRulesR[columnIdx] = cssRules[i];
          }
        }
      }
    }

    return <String, dom.CssStyleRule>{
      "left": _columnCssRulesL[idx],
      "right": _columnCssRulesR[idx]
    };
  }

  void _removeCssRules() {
    _style.remove();
    _stylesheet = null;
  }

  void destroy() {
    getEditorLock.cancelCurrentEdit();

    _eventBus.fire(core.Events.beforeDestroy, new core.BeforeDestroy(this));

    int i = _plugins.length;
    while (i-- > 0) {
      unregisterPlugin(_plugins[i]);
    }

    if (_gridOptions.enableColumnReorder) {
      _headers //.filter = new sort.Filter(":ui-sortable")
        ..sortable.destroy(); //("destroy"); // TODO
    }

    _unbindAncestorScrollEvents();
    // $container.unbind(".bwu-datagrid"); // TODO
    _removeCssRules();

    // $canvas.unbind("draginit dragstart dragend drag"); // TODO
    //$container
    //    ..children.clear();
    //this.classes.remove(uid);
  }

  //////////////////////////////////////////////////////////////////////////////////////////////
  // General

//  function trigger(evt, args, e) {
//    e = e || new EventData();
//    args = args || {};
//    args.grid = self;
//    return evt.notify(args, e, self);
//  }

  // TODO IEditor interface
  core.EditorLock get getEditorLock => _gridOptions.editorLock;

  // TODO IEditor interface
  EditController get getEditController => _editController;

  int getColumnIndex(Object id) => _columnsById[id];

  void autosizeColumns() {
    int i;
    Column c;
    List<int> widths = <int>[];
    int shrinkLeeway = 0;
    int total = 0;
    int prevTotal;
    int availWidth = _viewportHasVScroll
        ? _viewportW - _scrollbarDimensions.x.round()
        : _viewportW;

    for (i = 0; i < columns.length; i++) {
      c = columns[i];
      widths.add(c.width);
      total += c.width;
      if (c.resizable) {
        shrinkLeeway += c.width - math.max(c.minWidth, _absoluteColumnMinWidth);
      }
    }

    // shrink
    prevTotal = total;
    while (total > availWidth && shrinkLeeway != 0) {
      double shrinkProportion = (total - availWidth) / shrinkLeeway;
      for (i = 0; i < columns.length && total > availWidth; i++) {
        c = columns[i];
        final int width = widths[i];
        if (!c.resizable ||
            (width <= c.minWidth) ||
            width <= _absoluteColumnMinWidth) {
          continue;
        }
        final int absMinWidth = math.max(c.minWidth, _absoluteColumnMinWidth);
        int shrinkSize = (shrinkProportion * (width - absMinWidth)).floor();
        if (shrinkSize == 0) {
          shrinkSize = 1;
        }
        shrinkSize = math.min(shrinkSize, width - absMinWidth);
        total -= shrinkSize;
        shrinkLeeway -= shrinkSize;
        widths[i] -= shrinkSize;
      }
      if (prevTotal <= total) {
        // avoid infinite loop
        break;
      }
      prevTotal = total;
    }

    // grow
    prevTotal = total;
    while (total < availWidth) {
      final double growProportion = availWidth / total;
      for (i = 0; i < columns.length && total < availWidth; i++) {
        c = columns[i];
        final int currentWidth = widths[i];
        int growSize;

        if (!c.resizable ||
            (c.maxWidth != null && c.maxWidth <= currentWidth)) {
          growSize = 0;
        } else {
          final int tmp = c.maxWidth != null && (c.maxWidth - currentWidth) != 0
              ? c.maxWidth - currentWidth
              : 1000000;
          growSize = math.min(
              (growProportion * currentWidth).floor() - currentWidth, tmp);
          if (growSize == 0) {
            growSize = 1;
          }
        }
        total += growSize;
        widths[i] += growSize;
      }
      if (prevTotal >= total) {
        // avoid infinite loop
        break;
      }
      prevTotal = total;
    }

    bool reRender = false;
    for (i = 0; i < columns.length; i++) {
      if (columns[i].rerenderOnResize && columns[i].width != widths[i]) {
        reRender = true;
      }
      columns[i].width = widths[i];
    }

    _applyColumnHeaderWidths();
    _updateCanvasWidth(true);
    if (reRender) {
      invalidateAllRows();
      render();
    }
  }

  void _applyColumnHeaderWidths() {
    if (!_initialized) {
      return;
    }
    dom.Element h;
    for (int i = 0; i < _headers.children.length; i++) {
      h = _headers.children[i];
      if (h.clientWidth != columns[i].width - _headerColumnWidthDiff) {
        // TODO comparsion
        h.style.width = '${columns[i].width - _headerColumnWidthDiff}px';
      }
    }

    _updateColumnCaches();
  }

  bool _isPendingApplyColumnWith = false;
  bool _isApplyColumnWithActive = false;

  void _applyColumnWidths() {
    // only one active call at a time
    if (_isApplyColumnWithActive) {
      _isPendingApplyColumnWith = true;
    } else {
      _isApplyColumnWithActive = true;

      int x = 0;
      int w;
      Map<String, dom.CssStyleRule> rule;
      if (columns != null) {
        for (int i = 0; i < columns.length; i++) {
          w = columns[i].width;

          rule = _getColumnCssRules(i);
          rule['left'].style.left = '${x}px';
          rule['right'].style.right = '${(_canvasWidth - x - w)}px';

          x += columns[i].width;
        }
      }

      _isApplyColumnWithActive = false;
      if (_isPendingApplyColumnWith) {
        _isPendingApplyColumnWith = false;
        _applyColumnWidths();
      }
    }

//    String s = '';
//    stylesheet.rules.forEach((e) => s += "${e.cssText} ");
//    print(s);
//    $style.text = s;

    // $style.text = stylesheet.rules.join(' '); // TODO does this what it is intended for?
  }

  void setSortColumn(String columnId, bool ascending) {
    setSortColumns(<SortColumn>[new SortColumn(columnId, ascending)]);
  }

  void setSortColumns(List<SortColumn> cols) {
    _sortColumns = cols;

    List<BwuDatagridHeaderColumn> headerColumnEls =
        new List<BwuDatagridHeaderColumn>.from(_headers.children);
    headerColumnEls.forEach((BwuDatagridHeaderColumn hc) {
      hc
        ..classes.remove("bwu-datagrid-header-column-sorted")
        ..querySelectorAll(".bwu-datagrid-sort-indicator").forEach(
            (dom.Element e) => e.classes
              ..remove('bwu-datagrid-sort-indicator-asc')
              ..remove('bwu-datagrid-sort-indicator-desc'));
    });

    _sortColumns.forEach((SortColumn col) {
      if (col.sortAsc == null) {
        col.sortAsc = true;
      }
      int columnIndex = getColumnIndex(col.columnId);
      if (columnIndex != null) {
        headerColumnEls[columnIndex] // TODO verify
          ..classes.add("bwu-datagrid-header-column-sorted")
          ..querySelector(".bwu-datagrid-sort-indicator").classes.add(
              col.sortAsc
                  ? "bwu-datagrid-sort-indicator-asc"
                  : "bwu-datagrid-sort-indicator-desc");
      }
    });
  }

  List<SortColumn> get getSortColumns => _sortColumns;

  void _selectedRangesChangedHandler(core.SelectedRangesChanged e) {
    //dom.CustomEvent e, [List<Range> ranges]) {
    _selectedRows = <int>[];
    Map<int, Map<String, String>> hash = <int, Map<String, String>>{};
    for (int i = 0; i < e.ranges.length; i++) {
      for (int j = e.ranges[i].fromRow; j <= e.ranges[i].toRow; j++) {
        if (hash[j] == null) {
          // prevent duplicates
          _selectedRows.add(j);
          hash[j] = <String, String>{};
        }
        for (int k = e.ranges[i].fromCell; k <= e.ranges[i].toCell; k++) {
          if (canCellBeSelected(j, k)) {
            hash[j][columns[k].id] = _gridOptions.selectedCellCssClass;
          }
        }
      }
    }

    setCellCssStyles(_gridOptions.selectedCellCssClass, hash);

    _eventBus.fire(core.Events.selectedRowsChanged,
        new core.SelectedRowsChanged(this, getSelectedRows(), e.causedBy));
  }

  List<Column> get getColumns => columns;

  void _updateColumnCaches() {
    // Pre-calculate cell boundaries.
    _columnPosLeft = new List<int>(columns != null ? columns.length : 0);
    _columnPosRight = new List<int>(columns != null ? columns.length : 0);
    int x = 0;
    if (columns != null) {
      for (int i = 0; i < columns.length; i++) {
        _columnPosLeft[i] = x;
        _columnPosRight[i] = x + columns[i].width;
        x += columns[i].width;
      }
    }
  }

  set setColumns(List<Column> columnDefinitions) {
    _columns = columnDefinitions;

    _columnsById = <String, int>{};
    for (int i = 0; i < columns.length; i++) {
      Column m = columns[i] = new Column()
        ..extend(columnDefinitions[i])
        ..extend(columns[i]);
      _columnsById[m.id] = i;
      if (m.minWidth != null && (m.width == null || m.width < m.minWidth)) {
        m.width = m.minWidth;
      }
      if (m.maxWidth != null && m.width != null && m.width > m.maxWidth) {
        m.width = m.maxWidth;
      }
    }

    _updateColumnCaches();

    if (_initialized) {
      invalidateAllRows();
      _createColumnHeaders();
      _removeCssRules();
      _createCssRules();
      resizeCanvas();
      _applyColumnWidths();

      _handleScroll();
    }
  }

  // ===============================================================================================
  // Local Modifications -- new functions
  // ===============================================================================================
  /**
   * Trustwave Local Mod to fix columns on 2nd display
   */
  void reshowGrid() {
    if (_initialized) {
      invalidateAllRows();
      //_createColumnHeaders();
      _removeCssRules();
      _createCssRules();
      resizeCanvas();
      _applyColumnWidths();

      _handleScroll();
    }
  }

  /**
   * Trustwave Local Mod to fix column selection
   */
  dom.HtmlElement tw_bwu_closest(dom.HtmlElement e, String selector,
                             {dom.HtmlElement context, bool goThroughShadowBoundaries: false}) {
    dom.HtmlElement curr = e;

    print("---bwu---> ${selector}");
    String xselector = "${selector}${IGNORE_STYLE_SCOPE}";

    if (context != null) {
      //print('tools.closest: context not yet supported: ${context}');
    }

    dom.Node p = curr.parentNode;
    if (p is dom.ShadowRoot) {
      p = (p as dom.ShadowRoot).host;
    }

    dom.HtmlElement parent = (p as dom.HtmlElement);

    var prevParent = e;
    var found;
    while (parent != null && found == null) {
      print("---bwu---> parent: ${parent}, prevParent: ${prevParent}");
      found = parent.querySelector(xselector);
      print("---bwu------> found: ${found}");
      if (found != null) {
        if (parent.querySelectorAll(xselector).contains(prevParent)) {
          print("---bwu------> returning: ${prevParent}");
          return prevParent;
        } else {
          return found;
        }
      } else {
        if (parent.querySelectorAll(xselector).contains(prevParent)) {
          return prevParent;
        }
      }
      prevParent = parent;

      if (parent is dom.ShadowRoot) {
        if (goThroughShadowBoundaries) {
          parent = (parent as dom.ShadowRoot).host;
        }
      } else {
        parent = parent.parent;
      }
    }

    return found;
  }
  // ===============================================================================================
  // ===============================================================================================
  // ===============================================================================================

  GridOptions get getGridOptions => _gridOptions;

  set setGridOptions(GridOptions newGridOptions) {
    if (!getEditorLock.commitCurrentEdit()) {
      return;
    }

    _makeActiveCellNormal();

    if (_gridOptions.enableAddRow != newGridOptions.enableAddRow) {
      invalidateRow(getDataLength);
    }

    _gridOptions.extend(newGridOptions); // TODO verify
    _validateAndEnforceOptions();

    if(_viewport != null) {
      _viewport.style.overflowY = _gridOptions.autoHeight ? "hidden" : "auto";
    }
    render();
  }

  void _validateAndEnforceOptions() {
    if (_gridOptions.autoHeight) {
      _gridOptions.leaveSpaceForNewRows = false;
    }
  }

  void setData(DataProvider<core.ItemBase> newData,
      [bool scrollToTop = false]) {
    _dataProvider = newData;
    invalidateAllRows();
    updateRowCount();
    if (scrollToTop) {
      _scrollTo(0);
    }
  }

  int get getDataLength {
    if (_dataProvider != null) {
      return _dataProvider.length;
    } else {
      return 0;
    }
  }

  int _getDataLengthIncludingAddNew() {
    return getDataLength + (_gridOptions.enableAddRow ? 1 : 0);
  }

  core.ItemBase getDataItem(int i) {
    if (i >= _dataProvider.length) {
      return null;
    }
    return _dataProvider.getItem(i);
  }

  dom.Element get getTopPanel => _topPanel;

  set setTopPanelVisibility(bool visible) {
    if (_gridOptions.showTopPanel != visible) {
      _gridOptions.showTopPanel = visible;
      if (visible) {
        slideDown(_topPanelScroller,
            resizeCanvas); //.slideDown("fast", resizeCanvas);
      } else {
        slideUp(
            _topPanelScroller, resizeCanvas); //.slideUp("fast", resizeCanvas);
      }
    }
  }

  math.Rectangle<int> getCurrentSize(dom.Element e) {
    final String oldPos = e.style.position;
    final String oldDisplay = e.style.display;
    final int oldLeft = e.offsetLeft;
    e.style.left = '-10000px';
    e.style.display = 'block';
    math.Rectangle<int> size = new math.Rectangle<int>(
        0, 0, e.clientWidth.round(), e.clientHeight.round());
    e.style.display = oldDisplay;
    e.style.left = '${oldLeft}px';
    e.style.position = oldPos;
    return size;
  }

  void slideDown(dom.Element element, Function fn) {
    final math.Rectangle<int> size = getCurrentSize(element);
    element.style.height = '0';
    element.style.display = 'block';

    element.onTransitionEnd.first.then((dom.TransitionEvent e) {
      fn();
      element.classes.remove('slide-down');
    });

    new Future<Null>(() {
      element.classes.add('slide-down');
      element.style.height = '${size.height}px';
    });
  }

  void slideUp(dom.Element element, Function fn) {
    final int oldHeight = element.clientHeight.round();
    fn();
    element.classes.add('slide-up');

    element.onTransitionEnd.first.then((dom.TransitionEvent e) {
      element.classes.remove('slide-up');
      element.style.display = 'none';
      element.style.height = '${oldHeight}px';
    });

    new Future<Null>(() {
      element.style.height = '0';
    });
  }

  set setHeaderRowVisibility(bool visible) {
    if (_gridOptions.showHeaderRow != visible) {
      _gridOptions.showHeaderRow = visible;
      if (visible) {
        //_headerRowScroller.slideDown("fast", resizeCanvas);
      } else {
        //_headerRowScroller.slideUp("fast", resizeCanvas);
      }
    }
  }

  PolymerDom get getContainerNode => _container;

  //////////////////////////////////////////////////////////////////////////////////////////////
  // Rendering / Scrolling

  int _getRowTop(int row) {
    final int x = _gridOptions.rowHeight * row - _pageOffset;
    //print('rowTop - row: ${row}: ${x}');
    return x;
  }

  int _getRowFromPosition(int y) {
    return ((y + _pageOffset) / _gridOptions.rowHeight).floor();
  }

  void _scrollTo(int y) {
    y = math.max(y, 0);
    y = math.min(y,
        _th - _viewportH + (_viewportHasHScroll ? _scrollbarDimensions.y : 0));

    final int oldOffset = _pageOffset;

    _page = math.min(_n - 1, (y / _ph).floor());
    _pageOffset = (_page * _cj).round();
    int newScrollTop = y - _pageOffset;

    if (_pageOffset != oldOffset) {
      Range range = _getVisibleRange(newScrollTop);
      _cleanupRows(range);
      _updateRowPositions();
    }

    if (_prevScrollTop != newScrollTop) {
      _vScrollDir =
          (_prevScrollTop + oldOffset < newScrollTop + _pageOffset) ? 1 : -1;
      _viewport.scrollTop =
          (_lastRenderedScrollTop = _scrollTop = _prevScrollTop = newScrollTop);

      _eventBus.fire(
          core.Events.viewportChanged, new core.ViewportChanged(this));
    }
  }

  Formatter _getFormatter(int row, Column column) {
    RowMetadata rowMetadata =
        dataProvider != null && dataProvider.getItemMetadata != null
            ? dataProvider.getItemMetadata(row)
            : null;

    // look up by id, then index
    Column columnOverrides = rowMetadata != null && rowMetadata.columns != null
        ? (rowMetadata.columns[column.id] != null
            ? rowMetadata.columns[column.id]
            : rowMetadata.columns['${getColumnIndex(column.id)}'])
        : null;

    Formatter result =
        (columnOverrides != null && columnOverrides.formatter != null)
            ? columnOverrides.formatter
            : (rowMetadata != null && rowMetadata.formatter != null
                ? rowMetadata.formatter
                : column.formatter); // TODO check
    if (result == null) {
      if (_gridOptions.formatterFactory != null) {
        result = _gridOptions.formatterFactory(column);
      }
    }
    if (result == null) {
      result = _gridOptions.defaultFormatter;
    }
    return result;
  }

  Editor _getEditor(int row, int cell) {
    final Column column = columns[cell];
    final RowMetadata rowMetadata =
        dataProvider != null && dataProvider.getItemMetadata != null
            ? dataProvider.getItemMetadata(row)
            : null;
    final Map<String, Column> columnMetadata =
        rowMetadata != null ? rowMetadata.columns : null;

    if (columnMetadata != null &&
        columnMetadata[column.id] != null &&
        columnMetadata[column.id].editor != null) {
      return columnMetadata[column.id].editor;
    }
    if (columnMetadata != null &&
        columnMetadata[cell] != null &&
        columnMetadata[cell].editor != null) {
      return columnMetadata[cell].editor;
    }

    return column.editor != null
        ? column.editor
        : (_gridOptions.editorFactory != null
            ? _gridOptions.editorFactory(column)
            : null);
  }

  Object _getDataItemValueForColumn(core.ItemBase item, Column columnDef) {
    if (_gridOptions.dataItemColumnValueExtractor != null) {
      return _gridOptions.dataItemColumnValueExtractor(item, columnDef);
    }
    return item[columnDef.field];
  }

  dom.Element _appendRowHtml(int row, Range range, int dataLength) {
    final core.ItemBase d = getDataItem(row);
    final bool dataLoading = row < dataLength && d == null;
    String rowCss =
        'bwu-datagrid-row ${dataLoading ? " loading" : ""} ${row == _activeRow
        ? " active"
        : ""} ${row % 2 == 1 ? " odd" : " even"}';

    if (d == null) {
      rowCss = '${rowCss} ${_gridOptions.addNewRowCssClass}';
    }

    RowMetadata metadata =
        dataProvider != null && dataProvider.getItemMetadata != null
            ? dataProvider.getItemMetadata(row)
            : null;

    if (metadata != null && metadata.cssClasses != null) {
      rowCss = '${rowCss} ${metadata.cssClasses}';
    }

    dom.Element rowElement = new dom.DivElement()
      ..classes.add('ui-widget-content')
      ..classes.addAll(rowCss.split(" ").where((String s) => s.length > 0))
      ..style.top = '${_getRowTop(row)}px';

    String colspan;
    Column m;
    if (columns != null) {
      for (int i = 0, ii = columns.length; i < ii; i++) {
        m = columns[i];
        colspan = '1';
        if (metadata != null && metadata.columns != null) {
          final Column columnData = metadata.columns[m.id] != null
              ? metadata.columns[m.id]
              : metadata.columns['$i'];
          colspan = columnData != null && columnData.colspan != null
              ? columnData.colspan
              : '1';
          if (colspan == "*") {
            colspan = '${ii - i}';
          }
        }

        // Do not render cells outside of the viewport.
        if (_columnPosRight[math.min(ii - 1, i + utils.parseInt(colspan) - 1)] >
            range.leftPx) {
          if (_columnPosLeft[i] > range.rightPx) {
            // All columns to the right are outside the range.
            break;
          }

          _appendCellHtml(rowElement, row, i, colspan, d);
        }

        int intColspan = utils.parseInt(colspan);
        if (intColspan > 1) {
          i += (intColspan - 1);
        }
      }
    }

    return rowElement;
  }

  void _appendCellHtml(dom.Element rowElement, int row, int cell,
      String colspan, core.ItemBase item) {
    final Column m = columns[cell];
    String cellCss = "bwu-datagrid-cell l${cell} r${math.min(
        columns.length - 1, cell + utils.parseInt(colspan) - 1)} ${
        (m.cssClass != null ? m.cssClass : '')}";
    if (row == _activeRow && cell == _activeCell) {
      cellCss = "${cellCss} active";
    }

    // TODO:  merge them together in the setter
    for (String key in _cellCssClasses.keys) {
      if (_cellCssClasses[key][row] != null &&
          _cellCssClasses[key][row][m.id] != null) {
        cellCss += (" " + _cellCssClasses[key][row][m.id]);
      }
    }

    dom.Element cellElement = new dom.DivElement()
      ..classes.addAll(cellCss.split(" ").where((String s) => s.length > 0));

    if (m.isDraggable) {
      cellElement.attributes['draggable'] = 'true';
    }

    rowElement.append(cellElement);

    // if there is a corresponding row (if not, this is the Add New row or this data hasn't been loaded yet)
    if (item != null) {
      Object value = _getDataItemValueForColumn(item,
          m); // TODO this distinction is already made in DefaultTotalsCellFormatter - so remove it here and make DefaultTotalsCellFormatter work with the signature of the default formatter
      Formatter fm = _getFormatter(row, m);
      if (fm is CellFormatter) {
        fm.format(cellElement, row, cell, value, m, item);
      } else if (fm is core.GroupTotalsFormatter) {
        fm.format(cellElement, item, m);
      }
    }

    _rowsCache[row].cellRenderQueue.add(cell);
    _rowsCache[row].cellColSpans[cell] = colspan;
  }

  void _cleanupRows(Range rangeToKeep) {
    for (int i = 0; i < _rowsCache.length; i++) {
      if ((i != _activeRow) &&
          (i < rangeToKeep.top || i > rangeToKeep.bottom)) {
        _removeRowFromCache(i);
      }
    }
  }

  void invalidate() {
    updateRowCount();
    invalidateAllRows();
    render();
  }

  void invalidateAllRows() {
    if (_currentEditor != null) {
      _makeActiveCellNormal();
    }
    _rowsCache.keys.toList().forEach((int e) => _removeRowFromCache(e));
  }

  void _removeRowFromCache(int row) {
    final RowCache cacheEntry = _rowsCache[row];
    if (cacheEntry == null) {
      return;
    }

    if (cacheEntry.rowNode != null) {
      // TODO is this ever be null
      if (_rowNodeFromLastMouseWheelEvent == cacheEntry.rowNode) {
        cacheEntry.rowNode.style.display = 'none';
        _zombieRowNodeFromLastMouseWheelEvent = _rowNodeFromLastMouseWheelEvent;
      } else {
        //$canvas.children[0].remove(cacheEntry.rowNode);
        cacheEntry.rowNode.remove(); // TODO remove/add event handlers?
      }
    }

    _rowsCache.remove(row);
    _postProcessedRows.remove(row);
    _renderedRows--;
    _counterRowsRemoved++;
  }

  void invalidateRows(List<int> rows) {
    int i;
//    var rl; // TODO(zoechi) why is it unused?
    if (rows == null || rows.length == 0) {
      return;
    }
    _vScrollDir = 0;
    for (i = 0; i < rows.length; i++) {
      if (_currentEditor != null && _activeRow == rows[i]) {
        _makeActiveCellNormal();
      }
      if (_rowsCache[rows[i]] != null) {
        _removeRowFromCache(rows[i]);
      }
    }
  }

  void invalidateRow(int row) {
    invalidateRows(<int>[row]);
  }

  void updateCell(int row, int cell) {
    final dom.Element cellNode = getCellNode(row, cell);
    if (cellNode == null) {
      return;
    }

    final Column m = columns[cell];
    final core.ItemBase d = getDataItem(row);
    if (_currentEditor != null && _activeRow == row && _activeCell == cell) {
      _currentEditor.loadValue(d);
    } else {
          // TODO(zoechi) the first parameter to the formatter seems to be missing (test)
          d != null
          ? (_getFormatter(row, m) as CellFormatter).format(
              cellNode, row, cell, _getDataItemValueForColumn(d, m), m, d)
          : cellNode.innerHtml = '';
      _invalidatePostProcessingResults(row);
    }
  }

  void updateRow(int row) {
    final RowCache cacheEntry = _rowsCache[row];
    if (cacheEntry == null) {
      return;
    }

    _ensureCellNodesInRowsCache(row);

    core.ItemBase d = getDataItem(row);

    for (int columnIdx in cacheEntry.cellNodesByColumnIdx.keys) {
      if (!cacheEntry.cellNodesByColumnIdx.containsKey(columnIdx)) {
        continue;
      }

      columnIdx = columnIdx | 0;
      final Column m = columns[columnIdx];
      final dom.Element node = cacheEntry.cellNodesByColumnIdx[columnIdx];

      if (row == _activeRow &&
          columnIdx == _activeCell &&
          _currentEditor != null) {
        _currentEditor.loadValue(d);
      } else if (d != null) {
        /*node.innerHtml =*/
        (_getFormatter(row, m) as CellFormatter).format(
            node, row, columnIdx, _getDataItemValueForColumn(d, m), m, d);
      } else {
        node.innerHtml = "";
      }
    }

    _invalidatePostProcessingResults(row);
  }

  int _getViewportHeight() {
    final dom.CssStyleDeclaration containerCs = getComputedStyle();
    final dom.CssStyleDeclaration headerScrollerCs =
        _headerScroller.getComputedStyle();

    int x = utils.parseIntDropUnit(containerCs.height) -
        utils.parseIntDropUnit(containerCs.paddingTop) -
        utils.parseIntDropUnit(containerCs.paddingBottom) -
        utils.parseIntDropUnit(headerScrollerCs.height) -
        _getVBoxDelta(_headerScroller) -
        (_gridOptions.showTopPanel
            ? _gridOptions.topPanelHeight + _getVBoxDelta(_topPanelScroller)
            : 0) -
        (_gridOptions.showHeaderRow
            ? _gridOptions.headerRowHeight + _getVBoxDelta(_headerRowScroller)
            : 0);
    //print('viewportHeight: ${x}');
    return x;
  }

  void resizeCanvas([dom.Event e]) {
    if (!_initialized) {
      return;
    }
    if (_gridOptions.autoHeight) {
      _viewportH = _gridOptions.rowHeight * _getDataLengthIncludingAddNew();
    } else {
      _viewportH = _getViewportHeight();
    }

    _numVisibleRows = (_viewportH / _gridOptions.rowHeight).ceil();
    _viewportW = this
        .clientWidth
        .round(); //tools.parseInt(this.getComputedStyle().width);
    if (!_gridOptions.autoHeight) {
      _viewport.style.height = "${_viewportH}px";
    }

    if (_gridOptions.forceFitColumns) {
      autosizeColumns();
    }

    updateRowCount();
    _handleScroll();
    // Since the width has changed, force the render() to reevaluate virtually rendered cells.
    _lastRenderedScrollLeft = -1;
    render();
  }

  void updateRowCount() {
    if (!_initialized) {
      return;
    }

    final int dataLengthIncludingAddNew = _getDataLengthIncludingAddNew();
    final int numberOfRows = dataLengthIncludingAddNew +
        (_gridOptions.leaveSpaceForNewRows ? _numVisibleRows - 1 : 0);

    final bool oldViewportHasVScroll = _viewportHasVScroll;
    // with autoHeight, we do not need to accommodate the vertical scroll bar
    _viewportHasVScroll = !_gridOptions.autoHeight &&
        (numberOfRows * _gridOptions.rowHeight > _viewportH);

    _makeActiveCellNormal();

    // remove the rows that are now outside of the data range
    // this helps avoid redundant calls to .removeRow() when the size of the data decreased by thousands of rows
    final int l = dataLengthIncludingAddNew - 1;

    final int rcLength = _rowsCache.length;
    for (int i = 0; i < rcLength; i++) {
      if (i >= l) {
        _removeRowFromCache(i);
      }
    }

    if (_activeCellNode != null && _activeRow > l) {
      resetActiveCell();
    }

    final double oldH = _h;
    _th = math.max(_gridOptions.rowHeight * numberOfRows,
        _viewportH - _scrollbarDimensions.y);
    if (_th < _maxSupportedCssHeight) {
      // just one page
      _h = _ph = _th.toDouble();
      _n = 1;
      _cj = 0.0;
    } else {
      // break into pages
      _h = _maxSupportedCssHeight.toDouble();
      _ph = _h / 100;
      _n = (_th / _ph).floor();
      _cj = (_th - _h) / (_n - 1);
    }

    if (_h != oldH) {
      _canvas.style.height = "${_h}px";
      _scrollTop = _viewport.scrollTop.round();
    }

    final bool oldScrollTopInRange =
        (_scrollTop + _pageOffset <= _th - _viewportH);

    if (_th == 0 || _scrollTop == 0) {
      _page = _pageOffset = 0;
    } else if (oldScrollTopInRange) {
      // maintain virtual position
      _scrollTo(_scrollTop + _pageOffset);
    } else {
      // scroll to bottom
      _scrollTo((_th - _viewportH).round());
    }

    if (_h != oldH && _gridOptions.autoHeight) {
      resizeCanvas();
    }

    if (_gridOptions.forceFitColumns &&
        oldViewportHasVScroll != _viewportHasVScroll) {
      autosizeColumns();
    }
    _updateCanvasWidth(false);
  }

  Range getViewport([int viewportTop, int viewportLeft]) =>
      _getVisibleRange(viewportTop, viewportLeft);

  Range _getVisibleRange([int viewportTop, int viewportLeft]) {
    if (viewportTop == null) {
      viewportTop = _scrollTop;
    }
    if (viewportLeft == null) {
      viewportLeft = _scrollLeft;
    }

    return new Range(
        top: _getRowFromPosition(viewportTop),
        bottom: _getRowFromPosition(viewportTop + _viewportH) + 1,
        leftPx: viewportLeft,
        rightPx: viewportLeft + _viewportW);
  }

  Range getRenderedRange([int viewportTop, int viewportLeft]) {
    final Range range = _getVisibleRange(viewportTop, viewportLeft);
    int buffer = (_viewportH / _gridOptions.rowHeight).round();
    int minBuffer = 3;

    if (_vScrollDir == -1) {
      range.top -= buffer;
      range.bottom += minBuffer;
    } else if (_vScrollDir == 1) {
      range.top -= minBuffer;
      range.bottom += buffer;
    } else {
      range.top -= minBuffer;
      range.bottom += minBuffer;
    }

    range.top = math.max(0, range.top);
    range.bottom = math.min(_getDataLengthIncludingAddNew() - 1, range.bottom);

    range.leftPx -= _viewportW;
    range.rightPx += _viewportW;

    range.leftPx = math.max(0, range.leftPx);
    range.rightPx = math.min(_canvasWidth, range.rightPx);

    return range;
  }

  void _ensureCellNodesInRowsCache(int row) {
    final RowCache cacheEntry = _rowsCache[row];
    if (cacheEntry != null) {
      if (cacheEntry.cellRenderQueue.length > 0) {
        dom.Element lastChild = cacheEntry.rowNode.lastChild;
        while (cacheEntry.cellRenderQueue.length > 0) {
          final int columnIdx = cacheEntry.cellRenderQueue.removeLast();
          cacheEntry.cellNodesByColumnIdx[columnIdx] = lastChild;
          lastChild = lastChild.previousNode;
        }
      }
    }
  }

  void _cleanUpCells(Range range, int row) {
    final RowCache cacheEntry = _rowsCache[row];

    // Remove cells outside the range.
    final List<int> cellsToRemove = <int>[];
    for (int i in cacheEntry.cellNodesByColumnIdx.keys) {
      if (!cacheEntry.cellNodesByColumnIdx.containsKey(i)) {
        continue;
      }

      // TODO(zoechi) This is a string, so it needs to be cast back to a number.
      //i = i | 0;

      String colspan = cacheEntry.cellColSpans[i];
      int intColspan = utils.parseInt(colspan);
      if (_columnPosLeft[i] > range.rightPx ||
          _columnPosRight[math.min(columns.length - 1, i + intColspan - 1)] <
              range.leftPx) {
        if (!(row == _activeRow && i == _activeCell)) {
          cellsToRemove.add(i);
        }
      }
    }

    int cellToRemove;
    while (cellsToRemove.length > 0) {
      cellToRemove = cellsToRemove.removeLast();
      cacheEntry.cellNodesByColumnIdx[cellToRemove].remove();
      cacheEntry.cellColSpans.remove(cellToRemove);
      cacheEntry.cellNodesByColumnIdx.remove(cellToRemove);
      if (_postProcessedRows.containsKey(row)) {
        _postProcessedRows[row].remove(cellToRemove);
      }
    }
  }

  void _cleanUpAndRenderCells(Range range) {
    RowCache cacheEntry;
    final dom.Element rowElement = new dom.DivElement();
    final List<int> processedRows = <int>[];
    int cellsAdded;
    String colSpan;

    for (int row = range.top; row <= range.bottom; row++) {
      cacheEntry = _rowsCache[row];
      if (cacheEntry == null) {
        continue;
      }

      // cellRenderQueue populated in renderRows() needs to be cleared first
      _ensureCellNodesInRowsCache(row);

      _cleanUpCells(range, row);

      // Render missing cells.
      cellsAdded = 0;

      RowMetadata itemMetadata;
      if (dataProvider != null) {
        itemMetadata = dataProvider.getItemMetadata(row);
      }
      Map<String, Column> metadata =
          itemMetadata != null ? itemMetadata.columns : null;

      core.ItemBase d = getDataItem(row);

      // TODO:  shorten this loop (index? heuristics? binary search?)
      for (int i = 0, ii = columns.length; i < ii; i++) {
        // Cells to the right are outside the range.
        if (_columnPosLeft[i] > range.rightPx) {
          break;
        }

        int intColspan;
        // Already rendered.
        if ((colSpan = cacheEntry.cellColSpans[i]) != null) {
          intColspan = utils.parseInt(colSpan);
          i += (intColspan > 1 ? intColspan - 1 : 0);
          continue;
        }

        colSpan = '1';
        if (metadata != null) {
          final Column columnData = metadata[columns[i].id] != null
              ? metadata[columns[i].id]
              : metadata[i];
          colSpan = (columnData != null && columnData.colspan != null)
              ? columnData.colspan
              : '1';
          if (colSpan == "*") {
            colSpan = '${ii - i}';
          }
        }

        intColspan = utils.parseInt(colSpan);
        if (_columnPosRight[math.min(ii - 1, i + intColspan - 1)] >
            range.leftPx) {
          _appendCellHtml(rowElement, row, i, colSpan, d);
          cellsAdded++;
        }

        i += (intColspan > 1 ? intColspan - 1 : 0);
      }

      if (cellsAdded > 0) {
//        totalCellsAdded += cellsAdded; // TODO(zoechi) why is it unused?
        processedRows.add(row);
      }
    }

    if (rowElement.children.length == 0) {
      return;
    }

    final dom.DivElement x = new dom.DivElement();
    rowElement.children.forEach((dom.Element e) {
      x.append(e.clone(true));
    });

    int processedRow;
    dom.Element node;
    while (processedRows.length > 0 &&
        (processedRow = processedRows.removeLast()) != null) {
      cacheEntry = _rowsCache[processedRow];
      int columnIdx;
      while (cacheEntry.cellRenderQueue.length > 0) {
        columnIdx = cacheEntry.cellRenderQueue.removeLast();
        node = x.lastChild;
        cacheEntry.rowNode.append(node);
        cacheEntry.cellNodesByColumnIdx[columnIdx] = node;
      }
    }
  }

  void _renderRows(Range range) {
    final dom.Element parentNode = _canvas;

    List<int> rows = <int>[];
    bool needToReselectCell = false;
    int dataLength = getDataLength;

    final dom.DivElement x = new dom.DivElement();

    for (int i = range.top; i <= range.bottom; i++) {
      if (_rowsCache[i] != null) {
        continue;
      }
      _renderedRows++;
      rows.add(i);

      // Create an entry right away so that appendRowHtml() can
      // start populating it.
      _rowsCache[i] = new RowCache();
//        rowNode: null,
//
//        // ColSpans of rendered cells (by column idx).
//        // Can also be used for checking whether a cell has been rendered.
//        cellColSpans: [],
//
//        // Cell nodes (by column idx).  Lazy-populated by ensureCellNodesInRowsCache().
//        cellNodesByColumnIdx: [],
//
//        // Column indices of cell nodes that have been rendered, but not yet indexed in
//        // cellNodesByColumnIdx.  These are in the same order as cell nodes added at the
//        // end of the row.
//        cellRenderQueue: []
//      );

      x.append(_appendRowHtml(i, range, dataLength));
      if (_activeCellNode != null && _activeRow == i) {
        needToReselectCell = true;
      }
      _counterRowsRendered++;
    }

    if (rows.length == 0) {
      return;
    }

    for (int i = 0; i < rows.length; i++) {
      _rowsCache[rows[i]].rowNode = parentNode.append(x.firstChild);
      _rowsCache[rows[i]]
          .rowNode
          .querySelectorAll(".bwu-datagrid-cell${IGNORE_STYLE_SCOPE}")
          .forEach((dom.Element e) {
        e
          ..onMouseEnter.listen(_handleMouseEnter)
          ..onMouseLeave.listen(_handleMouseLeave);
      });
    }

    if (needToReselectCell) {
      _activeCellNode = getCellNode(_activeRow, _activeCell);
    }
  }

  /// Process async post-render tasks. Using post-render allows to render
  /// expensive content delayed to not hurt user experience, for example with
  /// scrolling.
  void _startPostProcessing() {
    if (!_gridOptions.enableAsyncPostRender) {
      return;
    }
    if (_postRenderHandle != null) {
      _postRenderHandle.cancel();
      _postRenderHandle = null;
    }
    _postRenderHandle =
        new Timer(_gridOptions.asyncPostRenderDelay, _asyncPostProcessRows);
  }

  void _invalidatePostProcessingResults(int row) {
    _postProcessedRows.remove(row);
    _postProcessFromRow = math.min(_postProcessFromRow, row);
    _postProcessToRow = math.max(_postProcessToRow, row);
    _startPostProcessing();
  }

  void _updateRowPositions() {
    for (final int row in _rowsCache.keys) {
      _rowsCache[row].rowNode.style.top = "${_getRowTop(row)}px";
    }
  }

  void render() {
    if (!_initialized) {
      return;
    }
    Range visible = _getVisibleRange();
    Range rendered = getRenderedRange();

    // remove rows no longer in the viewport
    _cleanupRows(rendered);

    // add new rows & missing cells in existing rows
    if (_lastRenderedScrollLeft != _scrollLeft) {
      _cleanUpAndRenderCells(rendered);
    }

    // render missing rows
    _renderRows(rendered);

    _postProcessFromRow = visible.top;
    _postProcessToRow =
        math.min(_getDataLengthIncludingAddNew() - 1, visible.bottom);
    _startPostProcessing();

    _lastRenderedScrollTop = _scrollTop;
    _lastRenderedScrollLeft = _scrollLeft;
    _renderHandle = null;
  }

  void _handleHeaderRowScroll([dom.Event e]) {
    final int scrollLeft = _headerRowScroller.scrollLeft;
    if (scrollLeft != _viewport.scrollLeft) {
      _viewport.scrollLeft = _scrollLeft;
    }
  }

  void _handleScroll([dom.Event e]) {
    _scrollTop = _viewport.scrollTop.round();
    _scrollLeft = _viewport.scrollLeft.round();
    int vScrollDist = (_scrollTop - _prevScrollTop).abs();
    int hScrollDist = (_scrollLeft - _prevScrollLeft).abs();

    if (hScrollDist != 0) {
      _prevScrollLeft = _scrollLeft;
      _headerScroller.scrollLeft = _scrollLeft;
      _topPanelScroller.scrollLeft = _scrollLeft;
      _headerRowScroller.scrollLeft = _scrollLeft;
    }

    if (vScrollDist != 0) {
      _vScrollDir = _prevScrollTop < _scrollTop ? 1 : -1;
      _prevScrollTop = _scrollTop;

      // switch virtual pages if needed
      if (vScrollDist < _viewportH) {
        _scrollTo(_scrollTop + _pageOffset);
      } else {
        final int oldOffset = _pageOffset;
        if (_h == _viewportH) {
          _page = 0;
        } else {
          _page = math.min(
              _n - 1,
              (_scrollTop *
                      ((_th - _viewportH) / (_h - _viewportH)) *
                      (1 / _ph))
                  .floor());
        }
        _pageOffset = (_page * _cj).round();
        if (oldOffset != _pageOffset) {
          invalidateAllRows();
        }
      }
    }

    if (hScrollDist != 0 || vScrollDist != 0) {
      if (_renderHandle != null) {
        _renderHandle.cancel();
      }

      if ((_lastRenderedScrollTop - _scrollTop).abs() > 20 ||
          (_lastRenderedScrollLeft - _scrollLeft).abs() > 20) {
        if (_gridOptions.forceSyncScrolling ||
            ((_lastRenderedScrollTop - _scrollTop).abs() < _viewportH &&
                (_lastRenderedScrollLeft - _scrollLeft).abs() < _viewportW)) {
          render();
        } else {
          _renderHandle = new Timer(new Duration(milliseconds: 50), render);
        }

        _eventBus.fire(
            core.Events.viewportChanged, new core.ViewportChanged(this));
      }
    }

    _eventBus.fire(core.Events.scroll,
        new core.Scroll(this, scrollLeft: _scrollLeft, scrollTop: _scrollTop));
  }

  void _asyncPostProcessRows() {
    final int dataLength = getDataLength;
    while (_postProcessFromRow <= _postProcessToRow) {
      final int row =
          (_vScrollDir >= 0) ? _postProcessFromRow++ : _postProcessToRow--;
      final RowCache cacheEntry = _rowsCache[row];
      if (cacheEntry == null || row >= dataLength) {
        continue;
      }

      if (_postProcessedRows[row] == null) {
        _postProcessedRows[row] = <bool>[]; // TODO {}
      }

      _ensureCellNodesInRowsCache(row);
      for (int columnIdx in cacheEntry.cellNodesByColumnIdx.keys) {
        if (!cacheEntry.cellNodesByColumnIdx.containsKey(columnIdx)) {
          continue;
        }

        // columnIdx = columnIdx | 0; // TODO

        final Column m = columns[columnIdx];
        if (m.asyncPostRender != null &&
            (_postProcessedRows[row].length < columnIdx ||
                _postProcessedRows[row][columnIdx] == null)) {
          final dom.Element node = cacheEntry.cellNodesByColumnIdx[columnIdx];
          if (node != null) {
            m.asyncPostRender(node, row, getDataItem(row), m);
          }
          if (_postProcessedRows[row].length <= columnIdx) {
            _postProcessedRows[row].length = columnIdx + 1;
          }
          _postProcessedRows[row][columnIdx] = true;
        }
      }

      _postRenderHandle =
          new Timer(_gridOptions.asyncPostRenderDelay, _asyncPostProcessRows);
      return;
    }
  }

  void _updateCellCssStylesOnRenderedRows(
      Map<int, Map<String, String>> addedHash,
      Map<int, Map<String, String>> removedHash) {
    dom.Element node;
//    String columnId; // TODO(zoechi) why is it unused?
    Map<String, String> addedRowHash;
    Map<String, String> removedRowHash;
    for (final int row in _rowsCache.keys) {
      // TODO check was probably associative array
      removedRowHash = removedHash != null ? removedHash[row] : null;
      addedRowHash = addedHash != null ? addedHash[row] : null;

      if (removedRowHash != null) {
        for (final Object columnId in removedRowHash.keys) {
          if (addedRowHash == null ||
              removedRowHash[columnId] != addedRowHash[columnId]) {
            node = getCellNode(row, getColumnIndex(columnId));
            if (node != null) {
              node.classes.remove(removedRowHash[columnId]);
            }
          }
        }
      }

      if (addedRowHash != null) {
        for (Object columnId in addedRowHash.keys) {
          if (removedRowHash == null ||
              removedRowHash[columnId] != addedRowHash[columnId]) {
            node = getCellNode(row, getColumnIndex(columnId));
            if (node != null) {
              node.classes.add(addedRowHash[columnId]);
            }
          }
        }
      }
    }
  }

  void addCellCssStyles(String key, Map<int, Map<String, String>> hash) {
    if (_cellCssClasses[key] != null) {
      throw "addCellCssStyles: cell CSS hash with key '" +
          key +
          "' already exists.";
    }

    _cellCssClasses[key] = hash;
    _updateCellCssStylesOnRenderedRows(hash, null);

    _eventBus.fire(core.Events.cellCssStylesChanged,
        new core.CellCssStylesChanged(this, key, hash: hash));
  }

  void removeCellCssStyles(String key) {
    if (_cellCssClasses[key] == null) {
      return;
    }

    _updateCellCssStylesOnRenderedRows(null, _cellCssClasses[key]);
    _cellCssClasses.remove(key);

    _eventBus.fire(core.Events.cellCssStylesChanged,
        new core.CellCssStylesChanged(this, key));
  }

  void setCellCssStyles(String key, Map<int, Map<String, String>> hash) {
    final Map<int, Map<String, String>> prevHash = _cellCssClasses[key];

    _cellCssClasses[key] = hash;
    _updateCellCssStylesOnRenderedRows(hash, prevHash);

    _eventBus.fire(core.Events.cellCssStylesChanged,
        new core.CellCssStylesChanged(this, key, hash: hash));
  }

  Map<int, Map<String, String>> getCellCssStyles(String key) {
    return _cellCssClasses[key];
  }

  void flashCell(int row, int cell, int speed) {
    speed = speed != null ? speed : 100;
    if (_rowsCache[row] != null) {
      final dom.Element cellElement = getCellNode(row, cell);

      Function toggleCellClass;
      toggleCellClass = (int times) {
        if (times == 0) {
          return;
        }
        new Future<Null>.delayed(new Duration(milliseconds: speed), () {
          cellElement.classes.toggle(_gridOptions.cellFlashingCssClass);
          new Future<Null>(() => toggleCellClass(times - 1));
        });
      };

      toggleCellClass(4);
    }
  }

  //////////////////////////////////////////////////////////////////////////////////////////////
  // Interactivity

  void _handleMouseWheel(dom.MouseEvent e) {
    final dom.Element rowNode =
        tw_bwu_closest((e.target as dom.Element), '.bwu-datagrid-row');
    if (rowNode != _rowNodeFromLastMouseWheelEvent) {
      if (_zombieRowNodeFromLastMouseWheelEvent != null &&
          _zombieRowNodeFromLastMouseWheelEvent != rowNode) {
        //$canvas.children[0].remove(zombieRowNodeFromLastMouseWheelEvent);
        if (_zombieRowNodeFromLastMouseWheelEvent != null) {
          // TODO check
          _zombieRowNodeFromLastMouseWheelEvent.remove();
        }
        _zombieRowNodeFromLastMouseWheelEvent = null;
      }
      _rowNodeFromLastMouseWheelEvent = rowNode;
    }
  }

  void _handleDrag(dom.MouseEvent e /*, [int dd]*/) {
    Cell cell = getCellFromEvent(e);
    if (cell == null || !_cellExists(cell.row, cell.cell)) {
      return; // false;
    }

    // execute async to work around events can't be fired within an event handler
    new Future<core.Drag>(() {
      final core.Drag data = _eventBus.fire(
          core.Events.drag, new core.Drag(this /*, dd: dd*/, causedBy: e));
      if (data.isDefaultPrevented) {
        return; //data.retVal;
      }

      // if nobody claims to be handling drag'n'drop by stopping immediate propagation,
      // cancel out of it
      //return false;
    });
  }

  void _handleDragStart(dom.MouseEvent e) {
    final Cell cell = getCellFromEvent(e);
    if (cell == null || !_cellExists(cell.row, cell.cell)) {
      e.preventDefault();
      return; // false;
    }

    final core.DragStart data = _eventBus.fire(
        core.Events.dragStart, new core.DragStart(this, causedBy: e));
    if (data.isDefaultPrevented) {
      return; // data.retVal;
    }

    //return false;
  }

//  bool _handleDragOver(dom.MouseEvent e, [Map dd]) {
//    return _eventBus.fire(core.Events.DRAG, new core.Drag(this, dd: dd, causedBy: e)).retVal;
//  }

  void _handleDragEnd(dom.MouseEvent e /*, [Map dd]*/) {
    _eventBus.fire(
        core.Events.dragEnd, new core.DragEnd(this /*, dd: dd*/, causedBy: e));
  }

  void _handleDragEnter(dom.MouseEvent e) {
    _eventBus.fire(
        core.Events.dragEnter, new core.DragEnter(this, causedBy: e));
  }

  void _handleDragLeave(dom.MouseEvent e) {
    _eventBus.fire(
        core.Events.dragLeave, new core.DragLeave(this, causedBy: e));
  }

  void _handleDragOver(dom.MouseEvent e) {
    _eventBus.fire(core.Events.dragOver, new core.DragOver(this, causedBy: e));
  }

  void _handleDrop(dom.MouseEvent e) {
    _eventBus.fire(core.Events.drop, new core.Drop(this, causedBy: e));
  }

//  // TODO I think this boolean return values are outdated - verify, what is the new way?
//  bool _handleCustomDrag(dom.CustomEvent e) {
//    Cell cell = getCellFromTarget((e.detail as cdrag.CustomDrag).target);
//    if (cell == null || !_cellExists(cell.row, cell.cell)) {
//      return false;
//    }
//
//    var data = _eventBus.fire(core.Events.CUSTOM_DRAG, new core.CustomDrag(this, causedByCustomDrag: e.detail as cdrag.CustomDrag));
//    if(data.isImmediatePropagationStopped) {
//      return data.retVal;
//    }
//
//    // if nobody claims to be handling drag'n'drop by stopping immediate propagation,
//    // cancel out of it
//    return false;
//  }
//
//  bool _handleCustomDragStart(dom.CustomEvent e) {
//    var cell = getCellFromTarget((e.detail as cdrag.CustomDrag).target);
//    if (cell == null|| !_cellExists(cell.row, cell.cell)) {
//      return false;
//    }
//
//    var data = _eventBus.fire(core.Events.CUSTOM_DRAG_START, new core.CustomDragStart(this, causedByCustomDrag: e.detail as cdrag.CustomDrag));
//    if (data.isImmediatePropagationStopped) {
//      return data.retVal;
//    }
//
//    return false;
//  }
//
//  void _handleCustomDragEnd(dom.CustomEvent e) {
//    _eventBus.fire(core.Events.CUSTOM_DRAG_END, new core.CustomDragEnd(this, causedByCustomDrag: e.detail as cdrag.CustomDrag));
//  }

  void _handleKeyDown(dom.KeyboardEvent e) {
    final core.KeyDown data = _eventBus.fire(core.Events.keyDown,
        new core.KeyDown(this, new Cell(_activeRow, _activeCell), causedBy: e));
    bool handled = data.isImmediatePropagationStopped;

    if (!handled) {
      if (!e.shiftKey && !e.altKey && !e.ctrlKey) {
        if (e.which == 27) {
          if (!getEditorLock.isActive) {
            return; // no editing mode to cancel, allow bubbling and default processing (exit without cancelling the event)
          }
          _cancelEditAndSetFocus();
        } else if (e.which == dom.KeyCode.NUM_SOUTH_EAST) {
          navigatePageDown();
          handled = true;
        } else if (e.which == dom.KeyCode.NUM_NORTH_EAST) {
          navigatePageUp();
          handled = true;
        } else if (e.which == dom.KeyCode.NUM_WEST) {
          handled = navigateLeft();
        } else if (e.which == dom.KeyCode.NUM_EAST) {
          handled = navigateRight();
        } else if (e.which == dom.KeyCode.NUM_NORTH) {
          handled = navigateUp();
        } else if (e.which == dom.KeyCode.NUM_SOUTH) {
          handled = navigateDown();
        } else if (e.which == dom.KeyCode.TAB) {
          handled = navigateNext();
        } else if (e.which == dom.KeyCode.ENTER) {
          if (_gridOptions.editable) {
            if (_currentEditor != null) {
              // adding new row
              if (_activeRow == getDataLength) {
                navigateDown();
              } else {
                _commitEditAndSetFocus();
              }
            } else {
              if (getEditorLock.commitCurrentEdit()) {
                _makeActiveCellEditable();
              }
            }
          }
          handled = true;
        }
      } else if (e.which == dom.KeyCode.TAB &&
          e.shiftKey &&
          !e.ctrlKey &&
          !e.altKey) {
        handled = navigatePrev();
      }
    }

    if (handled) {
      // the event has been handled so don't let parent element (bubbling/propagation) or browser (default) handle it
      e.stopPropagation();
      e.preventDefault();
//      try {
//        e.originalEvent.keyCode = 0; // prevent default behaviour for special keys in IE browsers (F3, F5, etc.)
//      }
//      // ignore exceptions - setting the original event's keycode throws access denied exception for "Ctrl"
//      // (hitting control key only, nothing else), "Shift" (maybe others)
//      catch (error) {
//      }
    }
  }

  void _handleClick(dom.MouseEvent e) {
    if (_currentEditor == null) {
      // if this click resulted in some cell child node getting focus,
      // don't steal it back - keyboard events will still bubble up
      // IE9+ seems to default DIVs to tabIndex=0 instead of -1, so check for cell clicks directly.
      if (e.target != dom.document.activeElement ||
          (e.target as dom.Element).classes.contains("bwu-datagrid-cell")) {
        setFocus();
      }
    }

    final Cell cell = getCellFromEvent(e);
    if (cell == null ||
        (_currentEditor != null &&
            _activeRow == cell.row &&
            _activeCell == cell.cell)) {
      return;
    }

    final core.Click data = _eventBus.fire(
        core.Events.click, new core.Click(this, cell, causedBy: e));
    if (data.isImmediatePropagationStopped) {
      return;
    }

    if ((_activeCell != cell.cell || _activeRow != cell.row) &&
        canCellBeActive(cell.row, cell.cell)) {
      if (!getEditorLock.isActive || getEditorLock.commitCurrentEdit()) {
        scrollRowIntoView(cell.row, false);
        _setActiveCellInternal(getCellNode(cell.row, cell.cell));
      }
    }
  }

  void _handleContextMenu(dom.MouseEvent e) {
    final Cell cell = getCellFromEvent(e);
    // TODO(zoechi)var $cell = tools.closest((e.target as dom.Element), '.bwu-datagrid-cell', context: $canvas);
    if (cell == null) {
      return;
    }

    // are we editing this cell?
    if (_activeCellNode == getCellNode(cell.row, cell.cell) &&
        _currentEditor != null) {
      return;
    }

    _eventBus.fire(
        core.Events.contextMenu, new core.ContextMenu(this, cell, causedBy: e));
  }

  void _handleDblClick(dom.Event e) {
    Cell cell = getCellFromEvent(e);
    if (cell == null ||
        (_currentEditor != null &&
            _activeRow == cell.row &&
            _activeCell == cell.cell)) {
      return;
    }

    final core.EventData data = _eventBus.fire(
        core.Events.doubleClick, new core.DoubleClick(this, cell, causedBy: e));
    if (data.isImmediatePropagationStopped) {
      return;
    }

    if (_gridOptions.editable) {
      gotoCell(cell.row, cell.cell, true);
    }
  }

  void _handleHeaderMouseEnter(dom.MouseEvent e) {
    _eventBus.fire(
        core.Events.headerMouseEnter,
        new core.HeaderMouseEnter(
            this, (e.target as BwuDatagridHeaderColumn).column,
            causedBy: e));
  }

  void _handleHeaderMouseLeave(dom.MouseEvent e) {
    _eventBus.fire(core.Events.headerMouseLeave,
        new core.HeaderMouseLeave(this, dataset['column'], causedBy: e));
  }

  void _handleHeaderContextMenu(dom.MouseEvent e) {
    final BwuDatagridHeaderColumn header = tw_bwu_closest(
            (e.target as dom.Element),
            ".bwu-datagread-header-column" /*, ".bwu-datagrid-header-columns"*/)
        as BwuDatagridHeaderColumn;
    final Column column = header != null ? header.column : null;
    _eventBus.fire(core.Events.headerContextMenu,
        new core.HeaderContextMenu(this, column, causedBy: e));
  }

  void _handleHeaderClick(dom.MouseEvent e) {
    final BwuDatagridHeaderColumn header = tw_bwu_closest(
            (e.target as dom.Element),
            '.bwu-datagrid-header-column' /*, ".bwu-datagrid-header-columns"*/)
        as BwuDatagridHeaderColumn;
    final Column column = header != null ? header.column : null;
    if (column != null) {
      _eventBus.fire(core.Events.headerClick,
          new core.HeaderClick(this, column, causedBy: e));
    }
  }

  void _handleMouseEnter(dom.MouseEvent e) {
    _eventBus.fire(
        core.Events.mouseEnter, new core.MouseEnter(this, causedBy: e));
  }

  void _handleMouseLeave(dom.MouseEvent e) {
    _eventBus.fire(
        core.Events.mouseLeave, new core.MouseLeave(this, causedBy: e));
  }

  bool _cellExists(int row, int cell) {
    return !(row < 0 ||
        row >= getDataLength ||
        cell < 0 ||
        cell >= columns.length);
  }

  Cell getCellFromPoint(int x, int y) {
    final int row = _getRowFromPosition(y);
    int cell = 0;

    int w = 0;
    for (int i = 0; i < columns.length && w < x; i++) {
      w += columns[i].width;
      cell++;
    }

    if (cell < 0) {
      cell = 0;
    }

    return new Cell(row, cell - 1);
  }

  int _getCellFromNode(dom.Element cellNode) {
    // read column number from .l<columnNumber> CSS class
    final Match matches =
        new RegExp(r'(?:\l)(\d+)').firstMatch(cellNode.className);
    //var cls = new RegExp(r'l\d+').allMatches(cellNode.className);
    if (matches == null) {
      throw "getCellFromNode: cannot get cell - ${cellNode.className}";
    }
    return utils.parseInt(matches.group(1));
  }

  int _getRowFromNode(dom.Element rowNode) {
    for (final int row in _rowsCache.keys) {
      // TODO in rowsCache) {
      if (_rowsCache[row] != null && _rowsCache[row].rowNode == rowNode) {
        return row;
      }
    }

    return null;
  }

  Cell getCellFromEvent(dom.Event e) {
    return getCellFromTarget(e.target as dom.Element);
  }

  Cell getCellFromTarget(dom.Element t) {
    final dom.Element cellElement =
        tw_bwu_closest(t, '.bwu-datagrid-cell', context: _canvas);
    if (cellElement == null) {
      return null;
    }

    int row = _getRowFromNode(cellElement.parentNode);
    final int cell = _getCellFromNode(cellElement);

    if (row == null || cell == null) {
      return null;
    } else {
      return new Cell(row, cell);
    }
  }

  NodeBox getCellNodeBox(int row, int cell) {
    if (!_cellExists(row, cell)) {
      return null;
    }

    final int y1 = _getRowTop(row);
    final int y2 = y1 + _gridOptions.rowHeight - 1;
    int x1 = 0;
    for (int i = 0; i < cell; i++) {
      x1 += columns[i].width;
    }
    final int x2 = x1 + columns[cell].width;

    // TODO shouldn't this be a rectangle?
    return new NodeBox(top: y1, left: x1, bottom: y2, right: x2);
  }

  //////////////////////////////////////////////////////////////////////////////////////////////
  // Cell switching

  void resetActiveCell() {
    _setActiveCellInternal(null, false);
  }

  void setFocus() {
    if (_tabbingDirection == -1) {
      _focusSink.focus();
    } else {
      _focusSink2.focus();
    }
  }

  void scrollCellIntoView(int row, int cell, [bool doPaging = false]) {
    scrollRowIntoView(row, doPaging);

    final String colspan = _getColspan(row, cell);
    int intColspan = utils.parseInt(colspan);
    final int left = _columnPosLeft[cell],
        right = _columnPosRight[cell + (intColspan > 1 ? intColspan - 1 : 0)],
        scrollRight = _scrollLeft + _viewportW;

    if (left < _scrollLeft) {
      _viewport.scrollLeft = left;
      _handleScroll();
      render();
    } else if (right > scrollRight) {
      _viewport.scrollLeft = math.min(left, right - _viewport.clientWidth);
      _handleScroll();
      render();
    }
  }

  void _setActiveCellInternal(dom.Element newCell, [bool optEditMode]) {
    if (_activeCellNode != null) {
      _makeActiveCellNormal();
      _activeCellNode.classes.remove("active");
      if (_rowsCache[_activeRow] != null) {
        _rowsCache[_activeRow].rowNode.classes.remove("active");
      }
    }

    final bool activeCellChanged = _activeCellNode != newCell;
    _activeCellNode = newCell;

    if (_activeCellNode != null) {
      _activeRow = _getRowFromNode(_activeCellNode.parentNode);
      _activeCell = _activePosX = _getCellFromNode(_activeCellNode);

      if (optEditMode == null) {
        optEditMode = (_activeRow == getDataLength) || _gridOptions.autoEdit;
      }

      _activeCellNode.classes.add("active");
      _rowsCache[_activeRow].rowNode.classes.add("active");

      if (_gridOptions.editable &&
          optEditMode &&
          _isCellPotentiallyEditable(_activeRow, _activeCell)) {
        if (_editorLoaderHandle != null) {
          _editorLoaderHandle.cancel();
        }
        if (_gridOptions.asyncEditorLoading) {
          _editorLoaderHandle =
              new Timer(_gridOptions.asyncEditorLoadDelay, () {
            _makeActiveCellEditable();
          });
        } else {
          _makeActiveCellEditable();
        }
      }
    } else {
      _activeRow = _activeCell = null;
    }

    if (activeCellChanged) {
      _eventBus.fire(core.Events.activeCellChanged,
          new core.ActiveCellChanged(this, getActiveCell()));
    }
  }

  void _clearTextSelection() {
//    if (dom.document.selection && dom.document.selection.empty) {
//      try {
//        //IE fails here if selected element is not in dom
//        dom.document.selection.empty();
//      } catch (e) { }
//    } else
//      if (dom.window.getSelection) {
    final dom.Selection sel = dom.window.getSelection();
    if (sel != null) {
      sel.removeAllRanges();
    }
//    }
  }

  bool _isCellPotentiallyEditable(int row, int cell) {
    final int dataLength = getDataLength;
    // is the data for this row loaded?
    if (row < dataLength && getDataItem(row) == null) {
      return false;
    }

    // are we in the Add New row?  can we create new from this cell?
    if (columns[cell].cannotTriggerInsert && row >= dataLength) {
      return false;
    }

    // does this cell have an editor?
    if (_getEditor(row, cell) == null) {
      return false;
    }

    return true;
  }

  void _makeActiveCellNormal() {
    if (_currentEditor == null) {
      return;
    }
    _eventBus.fire(core.Events.beforeCellEditorDestroy,
        new core.BeforeCellEditorDestroy(this, _currentEditor));
    _currentEditor.destroy();
    _currentEditor = null;

    if (_activeCellNode != null) {
      core.ItemBase d = getDataItem(_activeRow);
      _activeCellNode.classes..remove("editable")..remove("invalid");
      if (d != null) {
        final Column column = columns[_activeCell];
        CellFormatter formatter = _getFormatter(_activeRow, column);
        /*activeCellNode.innerHtml =*/
        formatter.format(_activeCellNode, _activeRow, _activeCell,
            _getDataItemValueForColumn(d, column), column, d);
        _invalidatePostProcessingResults(_activeRow);
      }
    }

    // if there previously was text selected on a page (such as selected text in the edit cell just removed),
    // IE can't set focus to anything else correctly
    if (dom.window.navigator.userAgent.toLowerCase().contains('msie')) {
      _clearTextSelection();
    }

    getEditorLock.deactivate(_editController);
  }

  void editActiveCell([Editor editor]) => _makeActiveCellEditable(editor);

  void _makeActiveCellEditable([Editor editor]) {
    if (_activeCellNode == null) {
      return;
    }
    if (!_gridOptions.editable) {
      throw "Grid : makeActiveCellEditable : should never get called when options.editable is false";
    }

    // cancel pending async call if there is one
    if (_editorLoaderHandle != null) {
      _editorLoaderHandle.cancel();
    }

    if (!_isCellPotentiallyEditable(_activeRow, _activeCell)) {
      return;
    }

    final Column columnDef = columns[_activeCell];
    final core.ItemBase item = getDataItem(_activeRow);

    if (!_eventBus
        .fire(
            core.Events.beforeEditCell,
            new core.BeforeEditCell(this,
                cell: new Cell(_activeRow, _activeCell),
                item: item,
                column: columnDef))
        .retVal) {
      setFocus();
      return;
    }

    getEditorLock.activate(_editController);
    _activeCellNode.classes.add("editable");

    // don't clear the cell if a custom editor is passed through
    if (editor == null) {
      _activeCellNode.innerHtml = "";
    }

    if (editor != null) {
      _currentEditor = editor;
    } else {
      _currentEditor = _getEditor(_activeRow, _activeCell);
    }
    _currentEditor = _currentEditor.newInstance(new EditorArgs(
        grid: this,
        gridPosition: _absBox(this),
        position: (_absBox(_activeCellNode)),
        container: _activeCellNode,
        column: columnDef,
        item: item != null ? item : new MapDataItem(),
        commitChanges: _commitEditAndSetFocus,
        cancelChanges: _cancelEditAndSetFocus));

    //currentEditor = new (editor || getEditor(activeRow, activeCell))({
//      'grid': this,
//      'gridPosition': absBox($container.children[0]),
//      'position': absBox(activeCellNode),
//      'container': activeCellNode,
//      'column': columnDef,
//      'item': item || {},
//      'commitChanges': commitEditAndSetFocus,
//      'cancelChanges': cancelEditAndSetFocus
//    });

    if (item != null) {
      _currentEditor.loadValue(item);
    }

    _serializedEditorValue = _currentEditor.serializeValue();

    if (_currentEditor.position != null) {
      _handleActiveCellPositionChange(null);
    }
  }

  void _commitEditAndSetFocus() {
    // if the commit fails, it would do so due to a validation error
    // if so, do not steal the focus from the editor
    if (getEditorLock.commitCurrentEdit()) {
      setFocus();
      if (_gridOptions.autoEdit) {
        navigateDown();
      }
    }
  }

  void _cancelEditAndSetFocus() {
    if (getEditorLock.cancelCurrentEdit()) {
      setFocus();
    }
  }

  NodeBox _absBox(dom.Element elem) {
    final dom.Rectangle<num> bcr = elem.getBoundingClientRect();
    final NodeBox box = new NodeBox(
        top: bcr.top.toInt(),
        left: bcr.left.toInt(),
        bottom: bcr.bottom.toInt(),
        right: bcr.right.toInt(),
        width: bcr.width.toInt(),
        height: bcr.height.toInt(),
        visible: true);
//    var cs = elem.getComputedStyle();
//    var box = new NodeBox(
//      top: elem.offsetTop,
//      left: elem.offsetLeft,
//      bottom: 0,
//      right: 0,
//      width: tools.outerWidth(elem), //tools.parseInt(cs.width) + tools.parseInt(cs.paddingLeft) + tools.parseInt(cs.paddingRight) + tools.parseInt(cs.borderLeft) + tools.parseInt(cs.borderRight), //elem.outerWidth(),
//      height: tools.outerHeight(elem), //parseInt(cs.height) + tools.parseInt(cs.paddingTop) + tools.parseInt(cs.paddingBottom) + tools.parseInt(cs.borderTop) + tools.parseInt(cs.borderBottom), //elem.outerHeight(), // TODO check all other outerWidth/outherHeight if they include border
//      visible: true);
//    box.bottom = box.top + box.height;
//    box.right = box.left + box.width;

    // walk up the tree
//    var offsetParent = elem.offsetParent;
//    while ((elem = tools.getParentElement(elem.parentNode)) != this) {
//      if (box.visible && elem.scrollHeight != elem.offsetHeight && elem.style.overflowY != "visible") {
//        box.visible = box.bottom > elem.scrollTop && box.top < elem.scrollTop + elem.clientHeight;
//      }
//
//      if (box.visible && elem.scrollWidth != elem.offsetWidth && elem.style.overflowX != "visible") {
//        box.visible = box.right > elem.scrollLeft && box.left < elem.scrollLeft + elem.clientWidth;
//      }
//
//      box.left -= elem.scrollLeft;
//      box.top -= elem.scrollTop;
//
//      if (elem == offsetParent) {
//        box.left += elem.offsetLeft;
//        box.top += elem.offsetTop;
//        offsetParent = elem.offsetParent;
//      }
//
//      box.bottom = box.top + box.height;
//      box.right = box.left + box.width;
//    }

    return box;
  }

  NodeBox getActiveCellPosition() {
    return _absBox(_activeCellNode);
  }

  NodeBox getGridPosition() {
    return _absBox(this);
  }

  void _handleActiveCellPositionChange(dom.Event e) {
    if (_activeCellNode == null) {
      return;
    }

    _eventBus.fire(core.Events.activeCellPositionChanged,
        new core.ActiveCellPositionChanged(this));

    if (_currentEditor != null) {
      final NodeBox cellBox = getActiveCellPosition();
      //if (currentEditor.show && currentEditor.hide) {
      if (!cellBox.visible) {
        _currentEditor.hide(); // TODO show/hide
      } else {
        _currentEditor.show();
      }
      //}

      _currentEditor.position(cellBox);
    }
  }

  Editor getCellEditor() {
    return _currentEditor;
  }

  Cell getActiveCell() {
    if (_activeCellNode == null) {
      return null;
    } else {
      return new Cell(_activeRow, _activeCell);
    }
  }

  dom.Element getActiveCellNode() {
    return _activeCellNode;
  }

  void scrollRowIntoView(int row, [bool doPaging = false]) {
    final int rowAtTop = row * _gridOptions.rowHeight;
    final int rowAtBottom = (row + 1) * _gridOptions.rowHeight -
        _viewportH +
        (_viewportHasHScroll ? _scrollbarDimensions.y : 0);

    // need to page down?
    if ((row + 1) * _gridOptions.rowHeight >
        _scrollTop + _viewportH + _pageOffset) {
      _scrollTo(doPaging ? rowAtTop : rowAtBottom);
      render();
    }
    // or page up?
    else if (row * _gridOptions.rowHeight < _scrollTop + _pageOffset) {
      _scrollTo(doPaging ? rowAtBottom : rowAtTop);
      render();
    }
  }

  void scrollRowToTop(int row) {
    _scrollTo(row * _gridOptions.rowHeight);
    render();
  }

  void _scrollPage(int dir) {
    final int deltaRows = dir * _numVisibleRows;
    _scrollTo(
        (_getRowFromPosition(_scrollTop) + deltaRows) * _gridOptions.rowHeight);
    render();

    if (_gridOptions.enableCellNavigation && _activeRow != null) {
      int row = _activeRow + deltaRows;
      final int dataLengthIncludingAddNew = _getDataLengthIncludingAddNew();
      if (row >= dataLengthIncludingAddNew) {
        row = dataLengthIncludingAddNew - 1;
      }
      if (row < 0) {
        row = 0;
      }

      int cell = 0;
      int prevCell;
      int prevActivePosX = _activePosX;
      while (cell <= _activePosX) {
        if (canCellBeActive(row, cell)) {
          prevCell = cell;
        }
        cell += int.parse(_getColspan(row, cell));
      }

      if (prevCell != null) {
        _setActiveCellInternal(getCellNode(row, prevCell));
        _activePosX = prevActivePosX;
      } else {
        resetActiveCell();
      }
    }
  }

  void navigatePageDown() => _scrollPage(1);

  void navigatePageUp() => _scrollPage(-1);

  String _getColspan(int row, int cell) {
    RowMetadata metadata =
        dataProvider != null && dataProvider.getItemMetadata != null
            ? dataProvider.getItemMetadata(row)
            : null;
    if (metadata == null || metadata.columns == null) {
      return '1';
    }

    Column columnData = metadata.columns[columns[cell].id] != null
        ? metadata.columns[columns[cell].id]
        : metadata.columns[cell];
    String colspan = columnData != null ? columnData.colspan : null;
    if (colspan == "*") {
      colspan = '${columns.length - cell}';
    } else {
      colspan = colspan != null ? colspan : '1';
    }

    return colspan;
  }

  int _findFirstFocusableCell(int row) {
    int cell = 0;
    while (cell < columns.length) {
      if (canCellBeActive(row, cell)) {
        return cell;
      }
      cell += int.parse(_getColspan(row, cell));
    }
    return null;
  }

  int _findLastFocusableCell(int row) {
    int cell = 0;
    int lastFocusableCell;
    while (cell < columns.length) {
      if (canCellBeActive(row, cell)) {
        lastFocusableCell = cell;
      }
      cell += utils.parseInt(_getColspan(row, cell));
    }
    return lastFocusableCell;
  }

  CellPos _gotoRight(int row, int cell, int posX) {
    if (cell >= columns.length) {
      return null;
    }

    do {
      cell += utils.parseInt(_getColspan(row, cell));
    } while (cell < columns.length && !canCellBeActive(row, cell));

    if (cell < columns.length) {
      return new CellPos(row: row, cell: cell, posX: cell);
    }
    return null;
  }

  CellPos _gotoLeft(int row, int cell, int posX) {
    if (cell <= 0) {
      return null;
    }

    final int firstFocusableCell = _findFirstFocusableCell(row);
    if (firstFocusableCell == null || firstFocusableCell >= cell) {
      return null;
    }

    CellPos prev = new CellPos(
        row: row, cell: firstFocusableCell, posX: firstFocusableCell);
    CellPos pos;
    while (true) {
      pos = _gotoRight(prev.row, prev.cell, prev.cell); //prev.posX']);
      if (pos == null) {
        return null;
      }
      if (pos.cell >= cell) {
        return prev;
      }
      prev = pos;
    }
  }

  CellPos _gotoDown(int row, int cell, int posX) {
    int prevCell;
    final int dataLengthIncludingAddNew = _getDataLengthIncludingAddNew();
    while (true) {
      if (++row >= dataLengthIncludingAddNew) {
        return null;
      }

      prevCell = cell = 0;
      while (cell <= posX) {
        prevCell = cell;
        cell += utils.parseInt(_getColspan(row, cell));
      }

      if (canCellBeActive(row, prevCell)) {
        return new CellPos(row: row, cell: prevCell, posX: posX);
      }
    }
  }

  CellPos _gotoUp(int row, int cell, int posX) {
    int prevCell;
    while (true) {
      if (--row < 0) {
        return null;
      }

      prevCell = cell = 0;
      while (cell <= posX) {
        prevCell = cell;
        cell += utils.parseInt(_getColspan(row, cell));
      }

      if (canCellBeActive(row, prevCell)) {
        return new CellPos(row: row, cell: prevCell, posX: posX);
      }
    }
  }

  CellPos _gotoNext(int row, int cell, int posX) {
    if (row == null && cell == null) {
      row = cell = posX = 0;
      if (canCellBeActive(row, cell)) {
        return new CellPos(row: row, cell: cell, posX: cell);
      }
    }

    final CellPos pos = _gotoRight(row, cell, posX);
    if (pos != null) {
      return pos;
    }

    int firstFocusableCell;
    final int dataLengthIncludingAddNew = _getDataLengthIncludingAddNew();
    while (++row < dataLengthIncludingAddNew) {
      firstFocusableCell = _findFirstFocusableCell(row);
      if (firstFocusableCell != null) {
        return new CellPos(
            row: row, cell: firstFocusableCell, posX: firstFocusableCell);
      }
    }
    return null;
  }

  CellPos _gotoPrev(int row, int cell, int posX) {
    if (row == null && cell == null) {
      row = _getDataLengthIncludingAddNew() - 1;
      cell = posX = columns.length - 1;
      if (canCellBeActive(row, cell)) {
        return new CellPos(row: row, cell: cell, posX: cell);
      }
    }

    CellPos pos;
    int lastSelectableCell;
    while (pos == null) {
      pos = _gotoLeft(row, cell, posX);
      if (pos != null) {
        break;
      }
      if (--row < 0) {
        return null;
      }

      cell = 0;
      lastSelectableCell = _findLastFocusableCell(row);
      if (lastSelectableCell != null) {
        pos = new CellPos(
            row: row, cell: lastSelectableCell, posX: lastSelectableCell);
      }
    }
    return pos;
  }

  bool navigateRight() {
    return _navigate("right");
  }

  bool navigateLeft() {
    return _navigate("left");
  }

  bool navigateDown() {
    return _navigate("down");
  }

  bool navigateUp() {
    return _navigate("up");
  }

  bool navigateNext() {
    return _navigate("next");
  }

  bool navigatePrev() {
    return _navigate("prev");
  }

  /// @param {string} dir Navigation direction.
  /// @return {boolean} Whether navigation resulted in a change of active cell.
  bool _navigate(String dir) {
    if (!_gridOptions.enableCellNavigation) {
      return false;
    }

    if (_activeCellNode == null && dir != "prev" && dir != "next") {
      return false;
    }

    if (!getEditorLock.commitCurrentEdit()) {
      return true;
    }
    setFocus();

    const Map<String, int> tabbingDirections = const <String, int>{
      "up": -1,
      "down": 1,
      "left": -1,
      "right": 1,
      "prev": -1,
      "next": 1
    };
    _tabbingDirection = tabbingDirections[dir];

    final Map<String, StepFunction> stepFunctions = <String, StepFunction>{
      "up": _gotoUp,
      "down": _gotoDown,
      "left": _gotoLeft,
      "right": _gotoRight,
      "prev": _gotoPrev,
      "next": _gotoNext
    };
    final StepFunction stepFn = stepFunctions[dir];
    final CellPos pos = stepFn(_activeRow, _activeCell, _activePosX);
    if (pos != null) {
      final bool isAddNewRow = (pos.row == getDataLength);
      scrollCellIntoView(pos.row, pos.cell, !isAddNewRow);
      _setActiveCellInternal(getCellNode(pos.row, pos.cell));
      _activePosX = pos.posX;
      return true;
    } else {
      _setActiveCellInternal(getCellNode(_activeRow, _activeCell));
      return false;
    }
  }

  dom.Element getCellNode(int row, int cell) {
    if (_rowsCache[row] != null) {
      _ensureCellNodesInRowsCache(row);
      return _rowsCache[row].cellNodesByColumnIdx[cell];
    }
    return null;
  }

  void setActiveCell(int row, int cell) {
    if (!_initialized) {
      return;
    }
    if (row > getDataLength || row < 0 || cell >= columns.length || cell < 0) {
      return;
    }

    if (!_gridOptions.enableCellNavigation) {
      return;
    }

    scrollCellIntoView(row, cell, false);
    _setActiveCellInternal(getCellNode(row, cell), false);
  }

  bool canCellBeActive(int row, int cell) {
    if (!_gridOptions.enableCellNavigation ||
        row >= _getDataLengthIncludingAddNew() ||
        row < 0 ||
        cell >= columns.length ||
        cell < 0) {
      return false;
    }

    RowMetadata rowMetadata =
        dataProvider != null && dataProvider.getItemMetadata != null
            ? dataProvider.getItemMetadata(row)
            : null;
    if (rowMetadata != null && rowMetadata.focusable == true) {
      return rowMetadata.focusable;
    }

    Map<String, Column> columnMetadata =
        rowMetadata != null ? rowMetadata.columns : null;
    if (columnMetadata != null &&
        columnMetadata[columns[cell].id] != null &&
        columnMetadata[columns[cell].id].focusable is bool) {
      return columnMetadata[columns[cell].id].focusable;
    }
    if (columnMetadata != null &&
        columnMetadata[cell] != null &&
        columnMetadata[cell].focusable is bool) {
      return columnMetadata[cell].focusable;
    }

    return columns[cell].focusable;
  }

  bool canCellBeSelected(int row, int cell) {
    if (row >= getDataLength || row < 0 || cell >= columns.length || cell < 0) {
      return false;
    }

    RowMetadata rowMetadata =
        dataProvider != null && dataProvider.getItemMetadata != null
            ? dataProvider.getItemMetadata(row)
            : null;
    if (rowMetadata != null && rowMetadata.selectable is bool) {
      return rowMetadata.selectable;
    }

    Column columnMetadata;
    if (rowMetadata != null && rowMetadata.columns != null) {
      if (rowMetadata.columns[columns[cell].id] != null) {
        columnMetadata = rowMetadata.columns[columns[cell].id];
      } else {
        columnMetadata = rowMetadata.columns[cell];
      }
    }
    if (columnMetadata != null && columnMetadata.selectable is bool) {
      return columnMetadata.selectable;
    }

    return columns[cell].selectable;
  }

  void gotoCell(int row, int cell, bool forceEdit) {
    if (!_initialized) {
      return;
    }
    if (!canCellBeActive(row, cell)) {
      return;
    }

    if (!getEditorLock.commitCurrentEdit()) {
      return;
    }

    scrollCellIntoView(row, cell, false);

    dom.Element newCell = getCellNode(row, cell);

    // if selecting the 'add new' row, start editing right away
    _setActiveCellInternal(
        newCell, forceEdit || (row == getDataLength) || _gridOptions.autoEdit);

    // if no editor was created, set the focus back on the grid
    if (_currentEditor == null) {
      setFocus();
    }
  }

  //////////////////////////////////////////////////////////////////////////////////////////////
  // IEditor implementation for the editor lock
  bool _commitCurrentEdit() {
    final core.ItemBase item = getDataItem(_activeRow);
    final Column column = columns[_activeCell];

    if (_currentEditor != null) {
      if (_currentEditor.isValueChanged) {
        final ValidationResult validationResults = _currentEditor.validate();

        if (validationResults.isValid) {
          if (_activeRow < getDataLength) {
            EditCommand editCommand;
            editCommand = new EditCommand(
                row: _activeRow,
                cell: _activeCell,
                editor: _currentEditor,
                serializedValue: _currentEditor.serializeValue(),
                prevSerializedValue: _serializedEditorValue,
                execute: () {
                  EditCommand cmd = editCommand;
                  cmd.editor.applyValue(item, cmd.serializedValue);
                  updateRow(cmd.row);
                  _eventBus.fire(
                      core.Events.cellChange,
                      new core.CellChange(
                          this, new Cell(_activeRow, _activeCell), item));
                },
                undo: () {
                  EditCommand cmd = editCommand;
                  cmd.editor.applyValue(item, cmd.prevSerializedValue);
                  updateRow(cmd.row);
                  _eventBus.fire(
                      core.Events.cellChange,
                      new core.CellChange(
                          this, new Cell(_activeRow, _activeCell), item));
                });

            if (_gridOptions.editCommandHandler != null) {
              _makeActiveCellNormal();
              _gridOptions.editCommandHandler(item, column, editCommand);
            } else {
              editCommand.execute();
              _makeActiveCellNormal();
            }
          } else {
            final MapDataItem newItem = new MapDataItem<dynamic,
                dynamic>(); // TODO should be the same as the type used by provided data?
            _currentEditor.applyValue(newItem, _currentEditor.serializeValue());
            _makeActiveCellNormal();
            _eventBus.fire(core.Events.addNewRow,
                new core.AddNewRow(this, newItem, column));
          }

          // check whether the lock has been re-acquired by event handlers
          return !getEditorLock.isActive;
        } else {
          // Re-add the CSS class to trigger transitions, if any.
          _activeCellNode.classes.remove("invalid");
          _activeCellNode.style
              .width; // force layout // TODO ob das in Dart so funktioniert
          _activeCellNode.classes.add("invalid");

          _eventBus.fire(
              core.Events.validationError,
              new core.ValidationError(this,
                  editor: _currentEditor,
                  cellNode: _activeCellNode,
                  validationResults: validationResults,
                  cell: new Cell(_activeRow, _activeCell),
                  column: column));

          _currentEditor.focus();
          return false;
        }
      }

      _makeActiveCellNormal();
    }
    return true;
  }

  bool _cancelCurrentEdit() {
    _makeActiveCellNormal();
    return true;
  }

  List<Range> _rowsToRanges(List<int> rows) {
    final List<Range> ranges = <Range>[];
    final int lastCell = columns.length - 1;
    for (int i = 0; i < rows.length; i++) {
      ranges.add(new Range(
          fromRow: rows[i], fromCell: 0, toRow: rows[i], toCell: lastCell));
    }
    return ranges;
  }

  List<int> getSelectedRows() {
    if (_selectionModel == null) {
      throw "Selection model is not set";
    }
    return _selectedRows;
  }

  void setSelectedRows(List<int> rows) {
    if (_selectionModel == null) {
      throw "Selection model is not set";
    }
    _selectionModel.setSelectedRanges(_rowsToRanges(rows));
  }

  //////////////////////////////////////////////////////////////////////////////////////////////
  // Debug
  void debug() {
    final String s = "counter_rows_rendered:  ${_counterRowsRendered}"
        "counter_rows_removed:  ${_counterRowsRemoved}"
        "renderedRows:  ${_renderedRows}"
        "numVisibleRows:  ${_numVisibleRows}"
        "maxSupportedCssHeight:  ${_maxSupportedCssHeight}"
        "n(umber of pages):  ${_n}"
        "(current) page:  ${_page}"
        "page height (ph):  ${_ph}";
    "vScrollDir:  ${_vScrollDir}";

    dom.window.alert(s);
  }

  Stream<core.ActiveCellChanged> get onBwuActiveCellChanged =>
      _eventBus.onEvent(core.Events.activeCellChanged);

  Stream<core.ActiveCellPositionChanged> get onBwuActiveCellPositionChanged =>
      _eventBus.onEvent(core.Events.activeCellPositionChanged);

  Stream<core.AddNewRow> get onBwuAddNewRow =>
      _eventBus.onEvent(core.Events.addNewRow);

  Stream<core.Attached> get onBwuAttached =>
      _eventBus.onEvent(core.Events.attached);

  Stream<core.BeforeCellEditorDestroy> get onBwuBeforeCellEditorDestroy =>
      _eventBus.onEvent(core.Events.beforeCellEditorDestroy);

  Stream<core.BeforeDestroy> get onBwuDestroy =>
      _eventBus.onEvent(core.Events.beforeDestroy);

  Stream<core.BeforeEditCell> get onBwuBeforeEditCell =>
      _eventBus.onEvent(core.Events.beforeEditCell);

  Stream<core.BeforeHeaderCellDestroy> get onBwuBeforeHeaderCellDestory =>
      _eventBus.onEvent(core.Events.beforeHeaderCellDestroy);

  Stream<core.BeforeHeaderRowCellDestroy> get onBwuBeforeHeaderRowCellDestory =>
      _eventBus.onEvent(core.Events.beforeHeaderRowCellDestroy);

  Stream<core.CellChange> get onBwuCellChange =>
      _eventBus.onEvent(core.Events.cellChange);

  Stream<core.CellCssStylesChanged> get onBwuCellCssStylesChanged =>
      _eventBus.onEvent(core.Events.cellCssStylesChanged);

  Stream<core.Click> get onBwuClick => _eventBus.onEvent(core.Events.click);

  Stream<core.ColumnsReordered> get onBwuColumnsReordered =>
      _eventBus.onEvent(core.Events.columnsReordered);

  Stream<core.ColumnsResized> get onBwuColumnsResized =>
      _eventBus.onEvent(core.Events.columnsResized);

  Stream<core.ContextMenu> get onBwuContextMenu =>
      _eventBus.onEvent(core.Events.contextMenu);

//  Stream<core.CustomDrag> get onBwuCustomDrag =>
//      _eventBus.onEvent(core.Events.CUSTOM_DRAG);
//
//  Stream<core.CustomDragEnd> get onBwuCustomDragEnd =>
//      _eventBus.onEvent(core.Events.CUSTOM_DRAG_END);
//
//  Stream<core.CustomDragStart> get onBwuCustomDragStart =>
//      _eventBus.onEvent(core.Events.CUSTOM_DRAG_START);
//
  Stream<core.DoubleClick> get onBwuDoubleClick =>
      _eventBus.onEvent(core.Events.doubleClick);

  Stream<core.Drag> get onBwuDrag => _eventBus.onEvent(core.Events.drag);

  Stream<core.DragEnd> get onBwuDragEnd =>
      _eventBus.onEvent(core.Events.dragEnd);

  Stream<core.DragEnter> get onBwuDragEnter =>
      _eventBus.onEvent(core.Events.dragEnter);

  Stream<core.DragLeave> get onBwuDragLeave =>
      _eventBus.onEvent(core.Events.dragLeave);

  Stream<core.DragOver> get onBwuDragOver =>
      _eventBus.onEvent(core.Events.dragOver);

// TODO this event is jQuery specific and not avaialble in Dart
//  Stream<core.DragInit> get onBwuDragInit =>
//      _eventBus.onEvent(core.Events.DRAG_INIT);

  Stream<core.DragStart> get onBwuDragStart =>
      _eventBus.onEvent(core.Events.dragStart);

  Stream<core.Drop> get onBwuDrop => _eventBus.onEvent(core.Events.drop);

  Stream<core.HeaderCellRendered> get onBwuHeaderCellRendered =>
      _eventBus.onEvent(core.Events.headerCellRendered);

  Stream<core.HeaderClick> get onBwuHeaderClick =>
      _eventBus.onEvent(core.Events.headerClick);

  Stream<core.HeaderContextMenu> get onBwuHeaderContextMenu =>
      _eventBus.onEvent(core.Events.headerContextMenu);

  Stream<core.HeaderMouseEnter> get onBwuHeaderMouseEnter =>
      _eventBus.onEvent(core.Events.headerMouseEnter);

  Stream<core.HeaderMouseLeave> get onBwuHeaderMouseLeave =>
      _eventBus.onEvent(core.Events.headerMouseLeave);

  Stream<core.HeaderRowCellRendered> get onBwuHeaderRowCellRendered =>
      _eventBus.onEvent(core.Events.headerRowCellRendered);

  Stream<core.KeyDown> get onBwuKeyDown =>
      _eventBus.onEvent(core.Events.keyDown);

  Stream<core.MouseEnter> get onBwuMouseEnter =>
      _eventBus.onEvent(core.Events.mouseEnter);

  Stream<core.MouseLeave> get onBwuMouseLeave =>
      _eventBus.onEvent(core.Events.mouseLeave);

  Stream<core.PasteCells> get onBwuPasteCells =>
      _eventBus.onEvent(core.Events.pasteCells);

  Stream<core.SelectedRangesChanged> get onBwuSelectedRangesChanged =>
      _eventBus.onEvent(core.Events.selectedRangesChanged);

  Stream<core.SelectedRowsChanged> get onBwuSelectedRowsChanged =>
      _eventBus.onEvent(core.Events.selectedRowsChanged);

  Stream<core.Scroll> get onBwuScroll => _eventBus.onEvent(core.Events.scroll);

  Stream<core.Sort> get onBwuSort => _eventBus.onEvent(core.Events.sort);

  Stream<core.ValidationError> get onBwuValidationError =>
      _eventBus.onEvent(core.Events.validationError);

  Stream<core.ViewportChanged> get onBwuViewportChanged =>
      _eventBus.onEvent(core.Events.viewportChanged);
}
