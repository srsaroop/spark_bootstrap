// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// This code was auto-generated, is not intended to be edited, and is subject to
// significant change. Please see the README file for more information.

library engine.index;

import 'dart:collection' show Queue;
import 'java_core.dart';
import 'java_engine.dart';
import 'source.dart';
import 'scanner.dart' show Token;
import 'ast.dart';
import 'element.dart';
import 'resolver.dart' show Namespace, NamespaceBuilder;
import 'engine.dart' show AnalysisEngine, AnalysisContext, InstrumentedAnalysisContextImpl, AngularHtmlUnitResolver;
import 'html.dart' as ht;

/**
 * Instances of the [RemoveSourceOperation] implement an operation that removes from the index
 * any data based on the content of a specified source.
 *
 * @coverage dart.engine.index
 */
class RemoveSourceOperation implements IndexOperation {
  /**
   * The index store against which this operation is being run.
   */
  IndexStore _indexStore;

  /**
   * The context in which source being removed.
   */
  AnalysisContext _context;

  /**
   * The source being removed.
   */
  final Source source;

  /**
   * Initialize a newly created operation that will remove the specified resource.
   *
   * @param indexStore the index store against which this operation is being run
   * @param context the [AnalysisContext] to remove source in
   * @param source the [Source] to remove from index
   */
  RemoveSourceOperation(IndexStore indexStore, AnalysisContext context, this.source) {
    this._indexStore = indexStore;
    this._context = context;
  }

  bool get isQuery => false;

  void performOperation() {
    {
      _indexStore.removeSource(_context, source);
    }
  }

  bool removeWhenSourceRemoved(Source source) => false;

  String toString() => "RemoveSource(${source.fullName})";
}

/**
 * The interface [IndexOperation] defines the behavior of objects used to perform operations
 * on an index.
 *
 * @coverage dart.engine.index
 */
abstract class IndexOperation {
  /**
   * Return `true` if this operation returns information from the index.
   *
   * @return `true` if this operation returns information from the index
   */
  bool get isQuery;

  /**
   * Perform the operation implemented by this operation.
   */
  void performOperation();

  /**
   * Return `true` if this operation should be removed from the operation queue when the
   * given resource has been removed.
   *
   * @param source the [Source] that has been removed
   * @return `true` if this operation should be removed from the operation queue as a
   *         result of removing the resource
   */
  bool removeWhenSourceRemoved(Source source);
}

/**
 * [IndexStore] which keeps full index in memory.
 *
 * @coverage dart.engine.index
 */
class MemoryIndexStoreImpl implements MemoryIndexStore {
  static Object _WEAK_SET_VALUE = new Object();

  /**
   * When logging is on, [AnalysisEngine] actually creates
   * [InstrumentedAnalysisContextImpl], which wraps [AnalysisContextImpl] used to create
   * actual [Element]s. So, in index we have to unwrap [InstrumentedAnalysisContextImpl]
   * when perform any operation.
   */
  static AnalysisContext unwrapContext(AnalysisContext context) {
    if (context is InstrumentedAnalysisContextImpl) {
      context = (context as InstrumentedAnalysisContextImpl).basis;
    }
    return context;
  }

  /**
   * @return the [Source] of the enclosing [LibraryElement], may be `null`.
   */
  static Source getLibrarySourceOrNull(Element element) {
    LibraryElement library = element.library;
    return library != null ? library.source : null;
  }

  /**
   * We add [AnalysisContext] to this weak set to ensure that we don't continue to add
   * relationships after some context was removed using [removeContext].
   */
  Expando _removedContexts = new Expando();

  /**
   * This map is used to canonicalize equal keys.
   */
  Map<MemoryIndexStoreImpl_ElementRelationKey, MemoryIndexStoreImpl_ElementRelationKey> _canonicalKeys = {};

  /**
   * The mapping of [ElementRelationKey] to the [Location]s, one-to-many.
   */
  Map<MemoryIndexStoreImpl_ElementRelationKey, Set<Location>> _keyToLocations = {};

  /**
   * The mapping of [Source] to the [ElementRelationKey]s. It is used in
   * [removeSource] to identify keys to remove from
   * [keyToLocations].
   */
  Map<AnalysisContext, Map<MemoryIndexStoreImpl_Source2, Set<MemoryIndexStoreImpl_ElementRelationKey>>> _contextToSourceToKeys = {};

  /**
   * The mapping of [Source] to the [Location]s existing in it. It is used in
   * [clearSource0] to identify locations to remove from
   * [keyToLocations].
   */
  Map<AnalysisContext, Map<MemoryIndexStoreImpl_Source2, List<Location>>> _contextToSourceToLocations = {};

  /**
   * The mapping of library [Source] to the [Source]s of part units.
   */
  Map<AnalysisContext, Map<Source, Set<Source>>> _contextToLibraryToUnits = {};

  /**
   * The mapping of unit [Source] to the [Source]s of libraries it is used in.
   */
  Map<AnalysisContext, Map<Source, Set<Source>>> _contextToUnitToLibraries = {};

  int _sourceCount = 0;

  int _keyCount = 0;

  int _locationCount = 0;

  bool aboutToIndex(AnalysisContext context, CompilationUnitElement unitElement) {
    context = unwrapContext(context);
    // may be already removed in other thread
    if (isRemovedContext(context)) {
      return false;
    }
    // validate unit
    if (unitElement == null) {
      return false;
    }
    LibraryElement libraryElement = unitElement.library;
    if (libraryElement == null) {
      return false;
    }
    CompilationUnitElement definingUnitElement = libraryElement.definingCompilationUnit;
    if (definingUnitElement == null) {
      return false;
    }
    // prepare sources
    Source library = definingUnitElement.source;
    Source unit = unitElement.source;
    // special handling for the defining library unit
    if (unit == library) {
      // prepare new parts
      Set<Source> newParts = new Set();
      for (CompilationUnitElement part in libraryElement.parts) {
        newParts.add(part.source);
      }
      // prepare old parts
      Map<Source, Set<Source>> libraryToUnits = _contextToLibraryToUnits[context];
      if (libraryToUnits == null) {
        libraryToUnits = {};
        _contextToLibraryToUnits[context] = libraryToUnits;
      }
      Set<Source> oldParts = libraryToUnits[library];
      // check if some parts are not in the library now
      if (oldParts != null) {
        Set<Source> noParts = oldParts.difference(newParts);
        for (Source noPart in noParts) {
          removeLocations(context, library, noPart);
        }
      }
      // remember new parts
      libraryToUnits[library] = newParts;
    }
    // remember libraries in which unit is used
    Map<Source, Set<Source>> unitToLibraries = _contextToUnitToLibraries[context];
    if (unitToLibraries == null) {
      unitToLibraries = {};
      _contextToUnitToLibraries[context] = unitToLibraries;
    }
    Set<Source> libraries = unitToLibraries[unit];
    if (libraries == null) {
      libraries = new Set();
      unitToLibraries[unit] = libraries;
    }
    libraries.add(library);
    // remove locations
    removeLocations(context, library, unit);
    // remove keys
    {
      Map<MemoryIndexStoreImpl_Source2, Set<MemoryIndexStoreImpl_ElementRelationKey>> sourceToKeys = _contextToSourceToKeys[context];
      if (sourceToKeys != null) {
        MemoryIndexStoreImpl_Source2 source2 = new MemoryIndexStoreImpl_Source2(library, unit);
        sourceToKeys.remove(source2);
      }
    }
    // OK, we can index
    return true;
  }

  bool aboutToIndex2(AnalysisContext context, Source source) {
    context = unwrapContext(context);
    // may be already removed in other thread
    if (isRemovedContext(context)) {
      return false;
    }
    // remove locations
    removeLocations(context, source, source);
    // remove keys
    {
      Map<MemoryIndexStoreImpl_Source2, Set<MemoryIndexStoreImpl_ElementRelationKey>> sourceToKeys = _contextToSourceToKeys[context];
      if (sourceToKeys != null) {
        MemoryIndexStoreImpl_Source2 source2 = new MemoryIndexStoreImpl_Source2(source, source);
        sourceToKeys.remove(source2);
      }
    }
    // OK, we can index
    return true;
  }

  List<Location> getRelationships(Element element, Relationship relationship) {
    MemoryIndexStoreImpl_ElementRelationKey key = new MemoryIndexStoreImpl_ElementRelationKey(element, relationship);
    Set<Location> locations = _keyToLocations[key];
    if (locations != null) {
      return new List.from(locations);
    }
    return Location.EMPTY_ARRAY;
  }

  String get statistics => "${_locationCount} relationships in ${_keyCount} keys in ${_sourceCount} sources";

  int internalGetKeyCount() => _keyToLocations.length;

  int internalGetLocationCount() {
    int count = 0;
    for (Set<Location> locations in _keyToLocations.values) {
      count += locations.length;
    }
    return count;
  }

  int internalGetLocationCount2(AnalysisContext context) {
    context = unwrapContext(context);
    int count = 0;
    for (Set<Location> locations in _keyToLocations.values) {
      for (Location location in locations) {
        if (identical(location.element.context, context)) {
          count++;
        }
      }
    }
    return count;
  }

  int internalGetSourceKeyCount(AnalysisContext context) {
    int count = 0;
    Map<MemoryIndexStoreImpl_Source2, Set<MemoryIndexStoreImpl_ElementRelationKey>> sourceToKeys = _contextToSourceToKeys[context];
    if (sourceToKeys != null) {
      for (Set<MemoryIndexStoreImpl_ElementRelationKey> keys in sourceToKeys.values) {
        count += keys.length;
      }
    }
    return count;
  }

  void recordRelationship(Element element, Relationship relationship, Location location) {
    if (element == null || location == null) {
      return;
    }
    location = location.clone();
    // at the index level we don't care about Member(s)
    if (element is Member) {
      element = (element as Member).baseElement;
    }
    // prepare information
    AnalysisContext elementContext = element.context;
    AnalysisContext locationContext = location.element.context;
    Source elementSource = element.source;
    Source locationSource = location.element.source;
    Source elementLibrarySource = getLibrarySourceOrNull(element);
    Source locationLibrarySource = getLibrarySourceOrNull(location.element);
    // sanity check
    if (locationContext == null) {
      return;
    }
    if (locationSource == null) {
      return;
    }
    if (elementContext == null && element is! NameElementImpl && element is! UniverseElementImpl) {
      return;
    }
    if (elementSource == null && element is! NameElementImpl && element is! UniverseElementImpl) {
      return;
    }
    // may be already removed in other thread
    if (isRemovedContext(elementContext)) {
      return;
    }
    if (isRemovedContext(locationContext)) {
      return;
    }
    // record: key -> location(s)
    MemoryIndexStoreImpl_ElementRelationKey key = getCanonicalKey(element, relationship);
    {
      Set<Location> locations = _keyToLocations.remove(key);
      if (locations == null) {
        locations = createLocationIdentitySet();
      } else {
        _keyCount--;
      }
      _keyToLocations[key] = locations;
      _keyCount++;
      locations.add(location);
      _locationCount++;
    }
    // record: location -> key
    location.internalKey = key;
    // prepare source pairs
    MemoryIndexStoreImpl_Source2 elementSource2 = new MemoryIndexStoreImpl_Source2(elementLibrarySource, elementSource);
    MemoryIndexStoreImpl_Source2 locationSource2 = new MemoryIndexStoreImpl_Source2(locationLibrarySource, locationSource);
    // record: element source -> keys
    {
      Map<MemoryIndexStoreImpl_Source2, Set<MemoryIndexStoreImpl_ElementRelationKey>> sourceToKeys = _contextToSourceToKeys[elementContext];
      if (sourceToKeys == null) {
        sourceToKeys = {};
        _contextToSourceToKeys[elementContext] = sourceToKeys;
      }
      Set<MemoryIndexStoreImpl_ElementRelationKey> keys = sourceToKeys[elementSource2];
      if (keys == null) {
        keys = new Set();
        sourceToKeys[elementSource2] = keys;
        _sourceCount++;
      }
      keys.remove(key);
      keys.add(key);
    }
    // record: location source -> locations
    {
      Map<MemoryIndexStoreImpl_Source2, List<Location>> sourceToLocations = _contextToSourceToLocations[locationContext];
      if (sourceToLocations == null) {
        sourceToLocations = {};
        _contextToSourceToLocations[locationContext] = sourceToLocations;
      }
      List<Location> locations = sourceToLocations[locationSource2];
      if (locations == null) {
        locations = [];
        sourceToLocations[locationSource2] = locations;
      }
      locations.add(location);
    }
  }

  void removeContext(AnalysisContext context) {
    context = unwrapContext(context);
    if (context == null) {
      return;
    }
    // mark as removed
    markRemovedContext(context);
    removeSources(context, null);
    // remove context
    _contextToSourceToKeys.remove(context);
    _contextToSourceToLocations.remove(context);
    _contextToLibraryToUnits.remove(context);
    _contextToUnitToLibraries.remove(context);
  }

  void removeSource(AnalysisContext context, Source unit) {
    context = unwrapContext(context);
    if (context == null) {
      return;
    }
    // remove locations defined in source
    Map<Source, Set<Source>> unitToLibraries = _contextToUnitToLibraries[context];
    if (unitToLibraries != null) {
      Set<Source> libraries = unitToLibraries.remove(unit);
      if (libraries != null) {
        for (Source library in libraries) {
          MemoryIndexStoreImpl_Source2 source2 = new MemoryIndexStoreImpl_Source2(library, unit);
          // remove locations defined in source
          removeLocations(context, library, unit);
          // remove keys for elements defined in source
          Map<MemoryIndexStoreImpl_Source2, Set<MemoryIndexStoreImpl_ElementRelationKey>> sourceToKeys = _contextToSourceToKeys[context];
          if (sourceToKeys != null) {
            Set<MemoryIndexStoreImpl_ElementRelationKey> keys = sourceToKeys.remove(source2);
            if (keys != null) {
              for (MemoryIndexStoreImpl_ElementRelationKey key in keys) {
                _canonicalKeys.remove(key);
                Set<Location> locations = _keyToLocations.remove(key);
                if (locations != null) {
                  _keyCount--;
                  _locationCount -= locations.length;
                }
              }
              _sourceCount--;
            }
          }
        }
      }
    }
  }

  void removeSources(AnalysisContext context, SourceContainer container) {
    context = unwrapContext(context);
    if (context == null) {
      return;
    }
    // remove sources #1
    Map<MemoryIndexStoreImpl_Source2, Set<MemoryIndexStoreImpl_ElementRelationKey>> sourceToKeys = _contextToSourceToKeys[context];
    if (sourceToKeys != null) {
      List<MemoryIndexStoreImpl_Source2> sources = [];
      for (MemoryIndexStoreImpl_Source2 source2 in sources) {
        Source source = source2._unitSource;
        if (container == null || container.contains(source)) {
          removeSource(context, source);
        }
      }
    }
    // remove sources #2
    Map<MemoryIndexStoreImpl_Source2, List<Location>> sourceToLocations = _contextToSourceToLocations[context];
    if (sourceToLocations != null) {
      List<MemoryIndexStoreImpl_Source2> sources = [];
      for (MemoryIndexStoreImpl_Source2 source2 in sources) {
        Source source = source2._unitSource;
        if (container == null || container.contains(source)) {
          removeSource(context, source);
        }
      }
    }
  }

  /**
   * Creates new [Set] that uses object identity instead of equals.
   */
  Set<Location> createLocationIdentitySet() => new Set<Location>.identity();

  /**
   * @return the canonical [ElementRelationKey] for given [Element] and
   *         [Relationship], i.e. unique instance for this combination.
   */
  MemoryIndexStoreImpl_ElementRelationKey getCanonicalKey(Element element, Relationship relationship) {
    MemoryIndexStoreImpl_ElementRelationKey key = new MemoryIndexStoreImpl_ElementRelationKey(element, relationship);
    MemoryIndexStoreImpl_ElementRelationKey canonicalKey = _canonicalKeys[key];
    if (canonicalKey == null) {
      canonicalKey = key;
      _canonicalKeys[key] = canonicalKey;
    }
    return canonicalKey;
  }

  /**
   * Checks if given [AnalysisContext] is marked as removed.
   */
  bool isRemovedContext(AnalysisContext context) => _removedContexts[context] != null;

  /**
   * Marks given [AnalysisContext] as removed.
   */
  void markRemovedContext(AnalysisContext context) {
    _removedContexts[context] = true;
  }

  /**
   * Removes locations recorded in the given library/unit pair.
   */
  void removeLocations(AnalysisContext context, Source library, Source unit) {
    MemoryIndexStoreImpl_Source2 source2 = new MemoryIndexStoreImpl_Source2(library, unit);
    Map<MemoryIndexStoreImpl_Source2, List<Location>> sourceToLocations = _contextToSourceToLocations[context];
    if (sourceToLocations != null) {
      List<Location> sourceLocations = sourceToLocations.remove(source2);
      if (sourceLocations != null) {
        for (Location location in sourceLocations) {
          MemoryIndexStoreImpl_ElementRelationKey key = location.internalKey as MemoryIndexStoreImpl_ElementRelationKey;
          Set<Location> relLocations = _keyToLocations[key];
          if (relLocations != null) {
            relLocations.remove(location);
            _locationCount--;
            // no locations with this key
            if (relLocations.isEmpty) {
              _canonicalKeys.remove(key);
              _keyToLocations.remove(key);
              _keyCount--;
            }
          }
        }
      }
    }
  }
}

class MemoryIndexStoreImpl_ElementRelationKey {
  Element _element;

  Relationship _relationship;

  MemoryIndexStoreImpl_ElementRelationKey(Element element, Relationship relationship) {
    this._element = element;
    this._relationship = relationship;
  }

  bool operator ==(Object obj) {
    MemoryIndexStoreImpl_ElementRelationKey other = obj as MemoryIndexStoreImpl_ElementRelationKey;
    Element otherElement = other._element;
    return identical(other._relationship, _relationship) && otherElement.nameOffset == _element.nameOffset && identical(otherElement.kind, _element.kind) && otherElement.displayName == _element.displayName && otherElement.source == _element.source;
  }

  int get hashCode => JavaArrays.makeHashCode([
      _element.source,
      _element.nameOffset,
      _element.kind,
      _element.displayName,
      _relationship]);

  String toString() => "${_element} ${_relationship}";
}

class MemoryIndexStoreImpl_Source2 {
  Source _librarySource;

  Source _unitSource;

  MemoryIndexStoreImpl_Source2(Source librarySource, Source unitSource) {
    this._librarySource = librarySource;
    this._unitSource = unitSource;
  }

  bool operator ==(Object obj) {
    if (identical(obj, this)) {
      return true;
    }
    if (obj is! MemoryIndexStoreImpl_Source2) {
      return false;
    }
    MemoryIndexStoreImpl_Source2 other = obj as MemoryIndexStoreImpl_Source2;
    return other._librarySource == _librarySource && other._unitSource == _unitSource;
  }

  int get hashCode => JavaArrays.makeHashCode([_librarySource, _unitSource]);

  String toString() => "${_librarySource} ${_unitSource}";
}

/**
 * Instances of the [IndexUnitOperation] implement an operation that adds data to the index
 * based on the resolved [CompilationUnit].
 *
 * @coverage dart.engine.index
 */
class IndexUnitOperation implements IndexOperation {
  /**
   * The index store against which this operation is being run.
   */
  IndexStore _indexStore;

  /**
   * The context in which compilation unit was resolved.
   */
  AnalysisContext _context;

  /**
   * The compilation unit being indexed.
   */
  final CompilationUnit unit;

  /**
   * The element of the compilation unit being indexed.
   */
  CompilationUnitElement _unitElement;

  /**
   * The source being indexed.
   */
  Source _source;

  /**
   * Initialize a newly created operation that will index the specified unit.
   *
   * @param indexStore the index store against which this operation is being run
   * @param context the context in which compilation unit was resolved
   * @param unit the fully resolved AST structure
   */
  IndexUnitOperation(IndexStore indexStore, AnalysisContext context, this.unit) {
    this._indexStore = indexStore;
    this._context = context;
    this._unitElement = unit.element;
    this._source = _unitElement.source;
  }

  /**
   * @return the [Source] to be indexed.
   */
  Source get source => _source;

  bool get isQuery => false;

  void performOperation() {
    {
      try {
        bool mayIndex = _indexStore.aboutToIndex(_context, _unitElement);
        if (!mayIndex) {
          return;
        }
        unit.accept(new IndexContributor(_indexStore));
        unit.accept(new AngularDartIndexContributor(_indexStore));
      } catch (exception) {
        AnalysisEngine.instance.logger.logError2("Could not index ${unit.element.location}", exception);
      }
    }
  }

  bool removeWhenSourceRemoved(Source source) => this._source == source;

  String toString() => "IndexUnitOperation(${_source.fullName})";
}

/**
 * Recursively visits [HtmlUnit] and every embedded [Expression].
 */
abstract class ExpressionVisitor extends ht.RecursiveXmlVisitor<Object> {
  /**
   * Visits the given [Expression]s embedded into tag or attribute.
   *
   * @param expression the [Expression] to visit, not `null`
   */
  void visitExpression(Expression expression);

  Object visitXmlAttributeNode(ht.XmlAttributeNode node) {
    visitExpressions(node.expressions);
    return super.visitXmlAttributeNode(node);
  }

  Object visitXmlTagNode(ht.XmlTagNode node) {
    visitExpressions(node.expressions);
    return super.visitXmlTagNode(node);
  }

  /**
   * Visits [Expression]s of the given [EmbeddedExpression]s.
   */
  void visitExpressions(List<ht.EmbeddedExpression> expressions) {
    for (ht.EmbeddedExpression embeddedExpression in expressions) {
      Expression expression = embeddedExpression.expression;
      visitExpression(expression);
    }
  }
}

/**
 * Relationship between an element and a location. Relationships are identified by a globally unique
 * identifier.
 *
 * @coverage dart.engine.index
 */
class Relationship {
  /**
   * The unique identifier for this relationship.
   */
  String _uniqueId;

  /**
   * A table mapping relationship identifiers to relationships.
   */
  static Map<String, Relationship> _RelationshipMap = {};

  /**
   * Return the relationship with the given unique identifier.
   *
   * @param uniqueId the unique identifier for the relationship
   * @return the relationship with the given unique identifier
   */
  static Relationship getRelationship(String uniqueId) {
    {
      Relationship relationship = _RelationshipMap[uniqueId];
      if (relationship == null) {
        relationship = new Relationship(uniqueId);
        _RelationshipMap[uniqueId] = relationship;
      }
      return relationship;
    }
  }

  /**
   * @return all registered [Relationship]s.
   */
  static Iterable<Relationship> values() => _RelationshipMap.values;

  /**
   * Initialize a newly created relationship to have the given unique identifier.
   *
   * @param uniqueId the unique identifier for this relationship
   */
  Relationship(String uniqueId) {
    this._uniqueId = uniqueId;
  }

  /**
   * Return the unique identifier for this relationship.
   *
   * @return the unique identifier for this relationship
   */
  String get identifier => _uniqueId;

  String toString() => _uniqueId;
}

/**
 * Implementation of [Index].
 *
 * @coverage dart.engine.index
 */
class IndexImpl implements Index {
  IndexStore _store;

  OperationQueue _queue;

  OperationProcessor _processor;

  IndexImpl(IndexStore store, OperationQueue queue, OperationProcessor processor) {
    this._store = store;
    this._queue = queue;
    this._processor = processor;
  }

  void getRelationships(Element element, Relationship relationship, RelationshipCallback callback) {
    _queue.enqueue(new GetRelationshipsOperation(_store, element, relationship, callback));
  }

  String get statistics => _store.statistics;

  void indexHtmlUnit(AnalysisContext context, ht.HtmlUnit unit) {
    if (unit == null) {
      return;
    }
    if (unit.element == null) {
      return;
    }
    if (unit.compilationUnitElement == null) {
      return;
    }
    _queue.enqueue(new IndexHtmlUnitOperation(_store, context, unit));
  }

  void indexUnit(AnalysisContext context, CompilationUnit unit) {
    if (unit == null) {
      return;
    }
    if (unit.element == null) {
      return;
    }
    _queue.enqueue(new IndexUnitOperation(_store, context, unit));
  }

  void removeContext(AnalysisContext context) {
    _queue.enqueue(new RemoveContextOperation(_store, context));
  }

  void removeSource(AnalysisContext context, Source source) {
    _queue.enqueue(new RemoveSourceOperation(_store, context, source));
  }

  void removeSources(AnalysisContext context, SourceContainer container) {
    _queue.enqueue(new RemoveSourcesOperation(_store, context, container));
  }

  void run() {
    _processor.run();
  }

  void stop() {
    _processor.stop(false);
  }
}

/**
 * Instances of the [RemoveSourcesOperation] implement an operation that removes from the
 * index any data based on the content of source belonging to a [SourceContainer].
 *
 * @coverage dart.engine.index
 */
class RemoveSourcesOperation implements IndexOperation {
  /**
   * The index store against which this operation is being run.
   */
  IndexStore _indexStore;

  /**
   * The context to remove container.
   */
  AnalysisContext _context;

  /**
   * The source container to remove.
   */
  final SourceContainer container;

  /**
   * Initialize a newly created operation that will remove the specified resource.
   *
   * @param indexStore the index store against which this operation is being run
   * @param context the [AnalysisContext] to remove container in
   * @param container the [SourceContainer] to remove from index
   */
  RemoveSourcesOperation(IndexStore indexStore, AnalysisContext context, this.container) {
    this._indexStore = indexStore;
    this._context = context;
  }

  bool get isQuery => false;

  void performOperation() {
    {
      _indexStore.removeSources(_context, container);
    }
  }

  bool removeWhenSourceRemoved(Source source) => false;

  String toString() => "RemoveSources(${container})";
}

/**
 * The interface `UniverseElement` defines element to use when we want to request "defines"
 * relations without specifying exact library.
 *
 * @coverage dart.engine.index
 */
abstract class UniverseElement implements Element {
  static final UniverseElement INSTANCE = UniverseElementImpl.INSTANCE;
}

/**
 * Instances of the [OperationProcessor] process the operations on a single
 * [OperationQueue]. Each processor can be run one time on a single thread.
 *
 * @coverage dart.engine.index
 */
class OperationProcessor {
  /**
   * The queue containing the operations to be processed.
   */
  OperationQueue _queue;

  /**
   * The current state of the processor.
   */
  ProcessorState _state = ProcessorState.READY;

  /**
   * The number of milliseconds for which the thread on which the processor is running will wait for
   * an operation to become available if there are no operations ready to be processed.
   */
  static int _WAIT_DURATION = 100;

  /**
   * Initialize a newly created operation processor to process the operations on the given queue.
   *
   * @param queue the queue containing the operations to be processed
   */
  OperationProcessor(OperationQueue queue) {
    this._queue = queue;
  }

  /**
   * Start processing operations. If the processor is already running on a different thread, then
   * this method will return immediately with no effect. Otherwise, this method will not return
   * until after the processor has been stopped from a different thread or until the thread running
   * the processor has been interrupted.
   */
  void run() {
    {
      // This processor is, or was, already running on a different thread.
      if (_state != ProcessorState.READY) {
        throw new IllegalStateException("Operation processors can only be run one time");
      }
      // OK, run.
      _state = ProcessorState.RUNNING;
    }
    try {
      while (isRunning) {
        // wait for operation
        IndexOperation operation = null;
        {
          operation = _queue.dequeue(_WAIT_DURATION);
        }
        // perform operation
        if (operation != null) {
          try {
            operation.performOperation();
          } catch (exception) {
            AnalysisEngine.instance.logger.logError2("Exception in indexing operation: ${operation}", exception);
          }
        }
      }
    } finally {
      {
        _state = ProcessorState.STOPPED;
      }
    }
  }

  /**
   * Stop processing operations after the current operation has completed. If the argument is
   * `true` then this method will wait until the last operation has completed; otherwise this
   * method might return before the last operation has completed.
   *
   * @param wait `true` if this method will wait until the last operation has completed before
   *          returning
   * @return the library files for the libraries that need to be analyzed when a new session is
   *         started.
   */
  List<Source> stop(bool wait) {
    {
      if (identical(_state, ProcessorState.READY)) {
        _state = ProcessorState.STOPPED;
        return unanalyzedSources;
      } else if (identical(_state, ProcessorState.STOPPED)) {
        return unanalyzedSources;
      } else if (identical(_state, ProcessorState.RUNNING)) {
        _state = ProcessorState.STOP_REQESTED;
      }
    }
    while (wait) {
      {
        if (identical(_state, ProcessorState.STOPPED)) {
          return unanalyzedSources;
        }
      }
      waitOneMs();
    }
    return unanalyzedSources;
  }

  /**
   * Waits until processors will switch from "ready" to "running" state.
   *
   * @return `true` if processor is now actually in "running" state, e.g. not in "stopped"
   *         state.
   */
  bool waitForRunning() {
    while (identical(_state, ProcessorState.READY)) {
      threadYield();
    }
    return identical(_state, ProcessorState.RUNNING);
  }

  /**
   * @return the [Source]s that are not indexed yet.
   */
  List<Source> get unanalyzedSources {
    Set<Source> sources = new Set();
    for (IndexOperation operation in _queue.operations) {
      if (operation is IndexUnitOperation) {
        Source source = operation.source;
        sources.add(source);
      }
    }
    return new List.from(sources);
  }

  /**
   * Return `true` if the current state is [ProcessorState#RUNNING].
   *
   * @return `true` if this processor is running
   */
  bool get isRunning {
    {
      return identical(_state, ProcessorState.RUNNING);
    }
  }

  void threadYield() {
  }

  void waitOneMs() {
  }
}

/**
 * The enumeration <code>ProcessorState</code> represents the possible states of an operation
 * processor.
 */
class ProcessorState extends Enum<ProcessorState> {
  /**
   * The processor is ready to be run (has not been run before).
   */
  static final ProcessorState READY = new ProcessorState('READY', 0);

  /**
   * The processor is currently performing operations.
   */
  static final ProcessorState RUNNING = new ProcessorState('RUNNING', 1);

  /**
   * The processor is currently performing operations but has been asked to stop.
   */
  static final ProcessorState STOP_REQESTED = new ProcessorState('STOP_REQESTED', 2);

  /**
   * The processor has stopped performing operations and cannot be used again.
   */
  static final ProcessorState STOPPED = new ProcessorState('STOPPED', 3);

  static final List<ProcessorState> values = [READY, RUNNING, STOP_REQESTED, STOPPED];

  ProcessorState(String name, int ordinal) : super(name, ordinal);
}

/**
 * Constants used when populating and accessing the index.
 *
 * @coverage dart.engine.index
 */
abstract class IndexConstants {
  /**
   * An element used to represent the universe.
   */
  static final Element UNIVERSE = UniverseElement.INSTANCE;

  /**
   * The relationship used to indicate that a container (the left-operand) contains the definition
   * of a class at a specific location (the right operand).
   */
  static final Relationship DEFINES_CLASS = Relationship.getRelationship("defines-class");

  /**
   * The relationship used to indicate that a container (the left-operand) contains the definition
   * of a function at a specific location (the right operand).
   */
  static final Relationship DEFINES_FUNCTION = Relationship.getRelationship("defines-function");

  /**
   * The relationship used to indicate that a container (the left-operand) contains the definition
   * of a class type alias at a specific location (the right operand).
   */
  static final Relationship DEFINES_CLASS_ALIAS = Relationship.getRelationship("defines-class-alias");

  /**
   * The relationship used to indicate that a container (the left-operand) contains the definition
   * of a function type at a specific location (the right operand).
   */
  static final Relationship DEFINES_FUNCTION_TYPE = Relationship.getRelationship("defines-function-type");

  /**
   * The relationship used to indicate that a container (the left-operand) contains the definition
   * of a method at a specific location (the right operand).
   */
  static final Relationship DEFINES_VARIABLE = Relationship.getRelationship("defines-variable");

  /**
   * The relationship used to indicate that a name (the left-operand) is defined at a specific
   * location (the right operand).
   */
  static final Relationship IS_DEFINED_BY = Relationship.getRelationship("is-defined-by");

  /**
   * The relationship used to indicate that a type (the left-operand) is extended by a type at a
   * specific location (the right operand).
   */
  static final Relationship IS_EXTENDED_BY = Relationship.getRelationship("is-extended-by");

  /**
   * The relationship used to indicate that a type (the left-operand) is implemented by a type at a
   * specific location (the right operand).
   */
  static final Relationship IS_IMPLEMENTED_BY = Relationship.getRelationship("is-implemented-by");

  /**
   * The relationship used to indicate that a type (the left-operand) is mixed into a type at a
   * specific location (the right operand).
   */
  static final Relationship IS_MIXED_IN_BY = Relationship.getRelationship("is-mixed-in-by");

  /**
   * The relationship used to indicate that a parameter or variable (the left-operand) is read at a
   * specific location (the right operand).
   */
  static final Relationship IS_READ_BY = Relationship.getRelationship("is-read-by");

  /**
   * The relationship used to indicate that a parameter or variable (the left-operand) is both read
   * and modified at a specific location (the right operand).
   */
  static final Relationship IS_READ_WRITTEN_BY = Relationship.getRelationship("is-read-written-by");

  /**
   * The relationship used to indicate that a parameter or variable (the left-operand) is modified
   * (assigned to) at a specific location (the right operand).
   */
  static final Relationship IS_WRITTEN_BY = Relationship.getRelationship("is-written-by");

  /**
   * The relationship used to indicate that an element (the left-operand) is referenced at a
   * specific location (the right operand). This is used for everything except read/write operations
   * for fields, parameters, and variables. Those use either [IS_REFERENCED_BY_QUALIFIED],
   * [IS_REFERENCED_BY_UNQUALIFIED], [IS_READ_BY], [IS_WRITTEN_BY] or
   * [IS_READ_WRITTEN_BY], as appropriate.
   */
  static final Relationship IS_REFERENCED_BY = Relationship.getRelationship("is-referenced-by");

  /**
   * The relationship used to indicate that an [NameElementImpl] (the left-operand) is
   * referenced at a specific location (the right operand). This is used for qualified resolved
   * references to methods and fields.
   */
  static final Relationship IS_REFERENCED_BY_QUALIFIED_RESOLVED = Relationship.getRelationship("is-referenced-by_qualified-resolved");

  /**
   * The relationship used to indicate that an [NameElementImpl] (the left-operand) is
   * referenced at a specific location (the right operand). This is used for qualified unresolved
   * references to methods and fields.
   */
  static final Relationship IS_REFERENCED_BY_QUALIFIED_UNRESOLVED = Relationship.getRelationship("is-referenced-by_qualified-unresolved");

  /**
   * The relationship used to indicate that an element (the left-operand) is referenced at a
   * specific location (the right operand). This is used for field accessors and methods.
   */
  static final Relationship IS_REFERENCED_BY_QUALIFIED = Relationship.getRelationship("is-referenced-by-qualified");

  /**
   * The relationship used to indicate that an element (the left-operand) is referenced at a
   * specific location (the right operand). This is used for field accessors and methods.
   */
  static final Relationship IS_REFERENCED_BY_UNQUALIFIED = Relationship.getRelationship("is-referenced-by-unqualified");

  /**
   * The relationship used to indicate that an element (the left-operand) is invoked at a specific
   * location (the right operand). This is used for functions.
   */
  static final Relationship IS_INVOKED_BY = Relationship.getRelationship("is-invoked-by");

  /**
   * The relationship used to indicate that an element (the left-operand) is invoked at a specific
   * location (the right operand). This is used for methods.
   */
  static final Relationship IS_INVOKED_BY_QUALIFIED = Relationship.getRelationship("is-invoked-by-qualified");

  /**
   * The relationship used to indicate that an element (the left-operand) is invoked at a specific
   * location (the right operand). This is used for methods.
   */
  static final Relationship IS_INVOKED_BY_UNQUALIFIED = Relationship.getRelationship("is-invoked-by-unqualified");
}

/**
 * Visits resolved [HtmlUnit] and adds relationships into [IndexStore].
 *
 * @coverage dart.engine.index
 */
class AngularHtmlIndexContributor extends ExpressionVisitor {
  /**
   * The [IndexStore] to record relations into.
   */
  IndexStore _store;

  /**
   * The index contributor used to index Dart [Expression]s.
   */
  IndexContributor _indexContributor;

  HtmlElement _htmlUnitElement;

  /**
   * Initialize a newly created Angular HTML index contributor.
   *
   * @param store the [IndexStore] to record relations into.
   */
  AngularHtmlIndexContributor(IndexStore store) {
    this._store = store;
    _indexContributor = new IndexContributor_AngularHtmlIndexContributor(store, this);
  }

  void visitExpression(Expression expression) {
    // NgFilter
    if (expression is SimpleIdentifier) {
      SimpleIdentifier identifier = expression;
      Element element = identifier.bestElement;
      if (element is AngularElement) {
        _store.recordRelationship(element, IndexConstants.IS_REFERENCED_BY, createLocation(identifier));
        return;
      }
    }
    // index as a normal Dart expression
    expression.accept(_indexContributor);
  }

  Object visitHtmlUnit(ht.HtmlUnit node) {
    _htmlUnitElement = node.element;
    CompilationUnitElement dartUnitElement = node.compilationUnitElement;
    _indexContributor.enterScope(dartUnitElement);
    return super.visitHtmlUnit(node);
  }

  Object visitXmlAttributeNode(ht.XmlAttributeNode node) {
    Element element = node.element;
    if (element != null) {
      ht.Token nameToken = node.nameToken;
      Location location = createLocation2(nameToken);
      _store.recordRelationship(element, IndexConstants.IS_REFERENCED_BY, location);
    }
    return super.visitXmlAttributeNode(node);
  }

  Object visitXmlTagNode(ht.XmlTagNode node) {
    Element element = node.element;
    if (element != null) {
      ht.Token tagToken = node.tagToken;
      Location location = createLocation2(tagToken);
      _store.recordRelationship(element, IndexConstants.IS_REFERENCED_BY, location);
    }
    return super.visitXmlTagNode(node);
  }

  Location createLocation(SimpleIdentifier identifier) => new Location(_htmlUnitElement, identifier.offset, identifier.length);

  Location createLocation2(ht.Token token) => new Location(_htmlUnitElement, token.offset, token.length);
}

class IndexContributor_AngularHtmlIndexContributor extends IndexContributor {
  final AngularHtmlIndexContributor AngularHtmlIndexContributor_this;

  IndexContributor_AngularHtmlIndexContributor(IndexStore arg0, this.AngularHtmlIndexContributor_this) : super(arg0);

  Element peekElement() => AngularHtmlIndexContributor_this._htmlUnitElement;

  void recordRelationship(Element element, Relationship relationship, Location location) {
    AngularElement angularElement = AngularHtmlUnitResolver.getAngularElement(element);
    if (angularElement != null) {
      element = angularElement;
      relationship = IndexConstants.IS_REFERENCED_BY;
    }
    super.recordRelationship(element, relationship, location);
  }
}

/**
 * The interface [Index] defines the behavior of objects that maintain an index storing
 * [Relationship] between [Element]. All of the operations
 * defined on the index are asynchronous, and results, when there are any, are provided through a
 * callback.
 *
 * Despite being asynchronous, the results of the operations are guaranteed to be consistent with
 * the expectation that operations are performed in the order in which they are requested.
 * Modification operations are executed before any read operation. There is no guarantee about the
 * order in which the callbacks for read operations will be invoked.
 *
 * @coverage dart.engine.index
 */
abstract class Index {
  /**
   * Asynchronously invoke the given callback with an array containing all of the locations of the
   * elements that have the given relationship with the given element. For example, if the element
   * represents a method and the relationship is the is-referenced-by relationship, then the
   * locations that will be passed into the callback will be all of the places where the method is
   * invoked.
   *
   * @param element the element that has the relationship with the locations to be returned
   * @param relationship the relationship between the given element and the locations to be returned
   * @param callback the callback that will be invoked when the locations are found
   */
  void getRelationships(Element element, Relationship relationship, RelationshipCallback callback);

  /**
   * Answer index statistics.
   */
  String get statistics;

  /**
   * Asynchronously process the given [HtmlUnit] in order to record the relationships.
   *
   * @param context the [AnalysisContext] in which [HtmlUnit] was resolved
   * @param unit the [HtmlUnit] being indexed
   */
  void indexHtmlUnit(AnalysisContext context, ht.HtmlUnit unit);

  /**
   * Asynchronously process the given [CompilationUnit] in order to record the relationships.
   *
   * @param context the [AnalysisContext] in which [CompilationUnit] was resolved
   * @param unit the [CompilationUnit] being indexed
   */
  void indexUnit(AnalysisContext context, CompilationUnit unit);

  /**
   * Asynchronously remove from the index all of the information associated with the given context.
   *
   * This method should be invoked when a context is disposed.
   *
   * @param context the [AnalysisContext] to remove
   */
  void removeContext(AnalysisContext context);

  /**
   * Asynchronously remove from the index all of the information associated with elements or
   * locations in the given source. This includes relationships between an element in the given
   * source and any other locations, relationships between any other elements and a location within
   * the given source.
   *
   * This method should be invoked when a source is no longer part of the code base.
   *
   * @param context the [AnalysisContext] in which [Source] being removed
   * @param source the [Source] being removed
   */
  void removeSource(AnalysisContext context, Source source);

  /**
   * Asynchronously remove from the index all of the information associated with elements or
   * locations in the given sources. This includes relationships between an element in the given
   * sources and any other locations, relationships between any other elements and a location within
   * the given sources.
   *
   * This method should be invoked when multiple sources are no longer part of the code base.
   *
   * @param the [AnalysisContext] in which [Source]s being removed
   * @param container the [SourceContainer] holding the sources being removed
   */
  void removeSources(AnalysisContext context, SourceContainer container);

  /**
   * Should be called in separate [Thread] to process request in this [Index]. Does not
   * return until the [stop] method is called.
   */
  void run();

  /**
   * Should be called to stop process running [run], so stop processing requests.
   */
  void stop();
}

/**
 * Container of information computed by the index - relationships between elements.
 *
 * @coverage dart.engine.index
 */
abstract class IndexStore {
  /**
   * Notifies the index store that we are going to index the unit with the given element.
   *
   * If the unit is a part of a library, then all its locations are removed. If it is a defining
   * compilation unit of a library, then index store also checks if some previously indexed parts of
   * the library are not parts of the library anymore, and clears their information.
   *
   * @param the [AnalysisContext] in which unit being indexed
   * @param unitElement the element of the unit being indexed
   * @return `true` the given [AnalysisContext] is active, or `false` if it was
   *         removed before, so no any unit may be indexed with it
   */
  bool aboutToIndex(AnalysisContext context, CompilationUnitElement unitElement);

  /**
   * Notifies the index store that we are going to index the given [Source].
   *
   * This method should be used only for a [Source] that cannot be a part of multiple
   * libraries. Otherwise [aboutToIndex] should be
   * used.
   *
   * @param the [AnalysisContext] in which unit being indexed
   * @param source the [Source] being indexed
   * @return `true` the given [AnalysisContext] is active, or `false` if it was
   *         removed before, so no any unit may be indexed with it
   */
  bool aboutToIndex2(AnalysisContext context, Source source);

  /**
   * Return the locations of the elements that have the given relationship with the given element.
   * For example, if the element represents a method and the relationship is the is-referenced-by
   * relationship, then the returned locations will be all of the places where the method is
   * invoked.
   *
   * @param element the the element that has the relationship with the locations to be returned
   * @param relationship the [Relationship] between the given element and the locations to be
   *          returned
   * @return the locations that have the given relationship with the given element
   */
  List<Location> getRelationships(Element element, Relationship relationship);

  /**
   * Answer index statistics.
   */
  String get statistics;

  /**
   * Record that the given element and location have the given relationship. For example, if the
   * relationship is the is-referenced-by relationship, then the element would be the element being
   * referenced and the location would be the point at which it is referenced. Each element can have
   * the same relationship with multiple locations. In other words, if the following code were
   * executed
   *
   * <pre>
   *   recordRelationship(element, isReferencedBy, location1);
   *   recordRelationship(element, isReferencedBy, location2);
   * </pre>
   *
   * then both relationships would be maintained in the index and the result of executing
   *
   * <pre>
   *   getRelationship(element, isReferencedBy);
   * </pre>
   *
   * would be an array containing both <code>location1</code> and <code>location2</code>.
   *
   * @param element the element that is related to the location
   * @param relationship the [Relationship] between the element and the location
   * @param location the [Location] where relationship happens
   */
  void recordRelationship(Element element, Relationship relationship, Location location);

  /**
   * Remove from the index all of the information associated with [AnalysisContext].
   *
   * This method should be invoked when a context is disposed.
   *
   * @param the [AnalysisContext] being removed
   */
  void removeContext(AnalysisContext context);

  /**
   * Remove from the index all of the information associated with elements or locations in the given
   * source. This includes relationships between an element in the given source and any other
   * locations, relationships between any other elements and a location within the given source.
   *
   * This method should be invoked when a source is no longer part of the code base.
   *
   * @param the [AnalysisContext] in which [Source] being removed
   * @param source the source being removed
   */
  void removeSource(AnalysisContext context, Source source);

  /**
   * Remove from the index all of the information associated with elements or locations in the given
   * sources. This includes relationships between an element in the given sources and any other
   * locations, relationships between any other elements and a location within the given sources.
   *
   * This method should be invoked when multiple sources are no longer part of the code base.
   *
   * @param the [AnalysisContext] in which [Source]s being removed
   * @param container the [SourceContainer] holding the sources being removed
   */
  void removeSources(AnalysisContext context, SourceContainer container);
}

/**
 * Implementation of [UniverseElement].
 *
 * @coverage dart.engine.index
 */
class UniverseElementImpl extends ElementImpl implements UniverseElement {
  static UniverseElementImpl INSTANCE = new UniverseElementImpl();

  UniverseElementImpl() : super.con2("--universe--", -1);

  accept(ElementVisitor visitor) => null;

  ElementKind get kind => ElementKind.UNIVERSE;
}

/**
 * Visits resolved AST and adds relationships into [IndexStore].
 *
 * @coverage dart.engine.index
 */
class IndexContributor extends GeneralizingASTVisitor<Object> {
  /**
   * @return the [Location] representing location of the [Element].
   */
  static Location createLocation(Element element) {
    if (element != null) {
      int offset = element.nameOffset;
      int length = element.displayName.length;
      return new Location(element, offset, length);
    }
    return null;
  }

  /**
   * @return the [ImportElement] that is referenced by this node with [PrefixElement],
   *         may be `null`.
   */
  static ImportElement getImportElement(SimpleIdentifier prefixNode) {
    IndexContributor_ImportElementInfo info = getImportElementInfo(prefixNode);
    return info != null ? info._element : null;
  }

  /**
   * @return the [ImportElementInfo] with [ImportElement] that is referenced by this
   *         node with [PrefixElement], may be `null`.
   */
  static IndexContributor_ImportElementInfo getImportElementInfo(SimpleIdentifier prefixNode) {
    IndexContributor_ImportElementInfo info = new IndexContributor_ImportElementInfo();
    // prepare environment
    ASTNode parent = prefixNode.parent;
    CompilationUnit unit = prefixNode.getAncestor(CompilationUnit);
    LibraryElement libraryElement = unit.element.library;
    // prepare used element
    Element usedElement = null;
    if (parent is PrefixedIdentifier) {
      PrefixedIdentifier prefixed = parent;
      usedElement = prefixed.staticElement;
      info._periodEnd = prefixed.period.end;
    }
    if (parent is MethodInvocation) {
      MethodInvocation invocation = parent;
      usedElement = invocation.methodName.staticElement;
      info._periodEnd = invocation.period.end;
    }
    // we need used Element
    if (usedElement == null) {
      return null;
    }
    // find ImportElement
    String prefix = prefixNode.name;
    Map<ImportElement, Set<Element>> importElementsMap = {};
    info._element = getImportElement2(libraryElement, prefix, usedElement, importElementsMap);
    if (info._element == null) {
      return null;
    }
    return info;
  }

  /**
   * @return the [ImportElement] that declares given [PrefixElement] and imports library
   *         with given "usedElement".
   */
  static ImportElement getImportElement2(LibraryElement libraryElement, String prefix, Element usedElement, Map<ImportElement, Set<Element>> importElementsMap) {
    // validate Element
    if (usedElement == null) {
      return null;
    }
    if (usedElement.enclosingElement is! CompilationUnitElement) {
      return null;
    }
    LibraryElement usedLibrary = usedElement.library;
    // find ImportElement that imports used library with used prefix
    List<ImportElement> candidates = null;
    for (ImportElement importElement in libraryElement.imports) {
      // required library
      if (importElement.importedLibrary != usedLibrary) {
        continue;
      }
      // required prefix
      PrefixElement prefixElement = importElement.prefix;
      if (prefix == null) {
        if (prefixElement != null) {
          continue;
        }
      } else {
        if (prefixElement == null) {
          continue;
        }
        if (prefix != prefixElement.name) {
          continue;
        }
      }
      // no combinators => only possible candidate
      if (importElement.combinators.length == 0) {
        return importElement;
      }
      // OK, we have candidate
      if (candidates == null) {
        candidates = [];
      }
      candidates.add(importElement);
    }
    // no candidates, probably element is defined in this library
    if (candidates == null) {
      return null;
    }
    // one candidate
    if (candidates.length == 1) {
      return candidates[0];
    }
    // ensure that each ImportElement has set of elements
    for (ImportElement importElement in candidates) {
      if (importElementsMap.containsKey(importElement)) {
        continue;
      }
      Namespace namespace = new NamespaceBuilder().createImportNamespace(importElement);
      Set<Element> elements = new Set();
      importElementsMap[importElement] = elements;
    }
    // use import namespace to choose correct one
    for (MapEntry<ImportElement, Set<Element>> entry in getMapEntrySet(importElementsMap)) {
      if (entry.getValue().contains(usedElement)) {
        return entry.getKey();
      }
    }
    // not found
    return null;
  }

  /**
   * If the given expression has resolved type, returns the new location with this type.
   *
   * @param location the base location
   * @param expression the expression assigned at the given location
   */
  static Location getLocationWithExpressionType(Location location, Expression expression) {
    if (expression != null) {
      return new LocationWithData<Type2>.con1(location, expression.bestType);
    }
    return location;
  }

  /**
   * If the given node is the part of the [ConstructorFieldInitializer], returns location with
   * type of the initializer expression.
   */
  static Location getLocationWithInitializerType(SimpleIdentifier node, Location location) {
    if (node.parent is ConstructorFieldInitializer) {
      ConstructorFieldInitializer initializer = node.parent as ConstructorFieldInitializer;
      if (identical(initializer.fieldName, node)) {
        location = getLocationWithExpressionType(location, initializer.expression);
      }
    }
    return location;
  }

  /**
   * If the given identifier has a synthetic [PropertyAccessorElement], i.e. accessor for
   * normal field, and it is LHS of assignment, then include [Type] of the assigned value into
   * the [Location].
   *
   * @param identifier the identifier to record location
   * @param element the element of the identifier
   * @param location the raw location
   * @return the [Location] with the type of the assigned value
   */
  static Location getLocationWithTypeAssignedToField(SimpleIdentifier identifier, Element element, Location location) {
    // we need accessor
    if (element is! PropertyAccessorElement) {
      return location;
    }
    PropertyAccessorElement accessor = element as PropertyAccessorElement;
    // should be setter
    if (!accessor.isSetter) {
      return location;
    }
    // accessor should be synthetic, i.e. field normal
    if (!accessor.isSynthetic) {
      return location;
    }
    // should be LHS of assignment
    ASTNode parent;
    {
      ASTNode node = identifier;
      parent = node.parent;
      // new T().field = x;
      if (parent is PropertyAccess) {
        PropertyAccess propertyAccess = parent as PropertyAccess;
        if (identical(propertyAccess.propertyName, node)) {
          node = propertyAccess;
          parent = propertyAccess.parent;
        }
      }
      // obj.field = x;
      if (parent is PrefixedIdentifier) {
        PrefixedIdentifier prefixedIdentifier = parent as PrefixedIdentifier;
        if (identical(prefixedIdentifier.identifier, node)) {
          node = prefixedIdentifier;
          parent = prefixedIdentifier.parent;
        }
      }
    }
    // OK, remember the type
    if (parent is AssignmentExpression) {
      AssignmentExpression assignment = parent as AssignmentExpression;
      Expression rhs = assignment.rightHandSide;
      location = getLocationWithExpressionType(location, rhs);
    }
    // done
    return location;
  }

  /**
   * @return `true` if given "node" is part of [PrefixedIdentifier] "prefix.node".
   */
  static bool isIdentifierInPrefixedIdentifier(SimpleIdentifier node) {
    ASTNode parent = node.parent;
    return parent is PrefixedIdentifier && identical(parent.identifier, node);
  }

  /**
   * @return `true` if given [SimpleIdentifier] is "name" part of prefixed identifier or
   *         method invocation.
   */
  static bool isQualified(SimpleIdentifier node) {
    ASTNode parent = node.parent;
    if (parent is PrefixedIdentifier) {
      return identical(parent.identifier, node);
    }
    if (parent is PropertyAccess) {
      return identical(parent.propertyName, node);
    }
    if (parent is MethodInvocation) {
      MethodInvocation invocation = parent;
      return invocation.realTarget != null && identical(invocation.methodName, node);
    }
    return false;
  }

  IndexStore _store;

  LibraryElement _libraryElement;

  Map<ImportElement, Set<Element>> _importElementsMap = {};

  /**
   * A stack whose top element (the element with the largest index) is an element representing the
   * inner-most enclosing scope.
   */
  Queue<Element> _elementStack = new Queue();

  IndexContributor(IndexStore store) {
    this._store = store;
  }

  /**
   * Enter a new scope represented by the given [Element].
   */
  void enterScope(Element element) {
    _elementStack.addFirst(element);
  }

  /**
   * @return the inner-most enclosing [Element], may be `null`.
   */
  Element peekElement() {
    for (Element element in _elementStack) {
      if (element != null) {
        return element;
      }
    }
    return null;
  }

  Object visitAssignmentExpression(AssignmentExpression node) {
    recordOperatorReference(node.operator, node.bestElement);
    return super.visitAssignmentExpression(node);
  }

  Object visitBinaryExpression(BinaryExpression node) {
    recordOperatorReference(node.operator, node.bestElement);
    return super.visitBinaryExpression(node);
  }

  Object visitClassDeclaration(ClassDeclaration node) {
    ClassElement element = node.element;
    enterScope(element);
    try {
      recordElementDefinition(element, IndexConstants.DEFINES_CLASS);
      {
        ExtendsClause extendsClause = node.extendsClause;
        if (extendsClause != null) {
          TypeName superclassNode = extendsClause.superclass;
          recordSuperType(superclassNode, IndexConstants.IS_EXTENDED_BY);
        } else {
          InterfaceType superType = element.supertype;
          if (superType != null) {
            ClassElement objectElement = superType.element;
            recordRelationship(objectElement, IndexConstants.IS_EXTENDED_BY, createLocation4(node.name.offset, 0));
          }
        }
      }
      {
        WithClause withClause = node.withClause;
        if (withClause != null) {
          for (TypeName mixinNode in withClause.mixinTypes) {
            recordSuperType(mixinNode, IndexConstants.IS_MIXED_IN_BY);
          }
        }
      }
      {
        ImplementsClause implementsClause = node.implementsClause;
        if (implementsClause != null) {
          for (TypeName interfaceNode in implementsClause.interfaces) {
            recordSuperType(interfaceNode, IndexConstants.IS_IMPLEMENTED_BY);
          }
        }
      }
      return super.visitClassDeclaration(node);
    } finally {
      exitScope();
    }
  }

  Object visitClassTypeAlias(ClassTypeAlias node) {
    ClassElement element = node.element;
    enterScope(element);
    try {
      recordElementDefinition(element, IndexConstants.DEFINES_CLASS_ALIAS);
      {
        TypeName superclassNode = node.superclass;
        if (superclassNode != null) {
          recordSuperType(superclassNode, IndexConstants.IS_EXTENDED_BY);
        }
      }
      {
        WithClause withClause = node.withClause;
        if (withClause != null) {
          for (TypeName mixinNode in withClause.mixinTypes) {
            recordSuperType(mixinNode, IndexConstants.IS_MIXED_IN_BY);
          }
        }
      }
      {
        ImplementsClause implementsClause = node.implementsClause;
        if (implementsClause != null) {
          for (TypeName interfaceNode in implementsClause.interfaces) {
            recordSuperType(interfaceNode, IndexConstants.IS_IMPLEMENTED_BY);
          }
        }
      }
      return super.visitClassTypeAlias(node);
    } finally {
      exitScope();
    }
  }

  Object visitCompilationUnit(CompilationUnit node) {
    CompilationUnitElement unitElement = node.element;
    if (unitElement != null) {
      _elementStack.add(unitElement);
      _libraryElement = unitElement.enclosingElement;
      if (_libraryElement != null) {
        return super.visitCompilationUnit(node);
      }
    }
    return null;
  }

  Object visitConstructorDeclaration(ConstructorDeclaration node) {
    ConstructorElement element = node.element;
    // define
    {
      Location location;
      if (node.name != null) {
        int start = node.period.offset;
        int end = node.name.end;
        location = createLocation4(start, end - start);
      } else {
        int start = node.returnType.end;
        location = createLocation4(start, 0);
      }
      recordRelationship(element, IndexConstants.IS_DEFINED_BY, location);
    }
    // visit children
    enterScope(element);
    try {
      return super.visitConstructorDeclaration(node);
    } finally {
      exitScope();
    }
  }

  Object visitConstructorName(ConstructorName node) {
    ConstructorElement element = node.staticElement;
    Location location;
    if (node.name != null) {
      int start = node.period.offset;
      int end = node.name.end;
      location = createLocation4(start, end - start);
    } else {
      int start = node.type.end;
      location = createLocation4(start, 0);
    }
    recordRelationship(element, IndexConstants.IS_REFERENCED_BY, location);
    return super.visitConstructorName(node);
  }

  Object visitExportDirective(ExportDirective node) {
    ExportElement element = node.element as ExportElement;
    if (element != null) {
      LibraryElement expLibrary = element.exportedLibrary;
      recordLibraryReference(node, expLibrary);
    }
    return super.visitExportDirective(node);
  }

  Object visitFormalParameter(FormalParameter node) {
    ParameterElement element = node.element;
    enterScope(element);
    try {
      return super.visitFormalParameter(node);
    } finally {
      exitScope();
    }
  }

  Object visitFunctionDeclaration(FunctionDeclaration node) {
    Element element = node.element;
    recordElementDefinition(element, IndexConstants.DEFINES_FUNCTION);
    enterScope(element);
    try {
      return super.visitFunctionDeclaration(node);
    } finally {
      exitScope();
    }
  }

  Object visitFunctionTypeAlias(FunctionTypeAlias node) {
    Element element = node.element;
    recordElementDefinition(element, IndexConstants.DEFINES_FUNCTION_TYPE);
    return super.visitFunctionTypeAlias(node);
  }

  Object visitImportDirective(ImportDirective node) {
    ImportElement element = node.element;
    if (element != null) {
      LibraryElement impLibrary = element.importedLibrary;
      recordLibraryReference(node, impLibrary);
    }
    return super.visitImportDirective(node);
  }

  Object visitIndexExpression(IndexExpression node) {
    MethodElement element = node.bestElement;
    if (element is MethodElement) {
      Token operator = node.leftBracket;
      Location location = createLocation5(operator);
      recordRelationship(element, IndexConstants.IS_INVOKED_BY_QUALIFIED, location);
    }
    return super.visitIndexExpression(node);
  }

  Object visitMethodDeclaration(MethodDeclaration node) {
    ExecutableElement element = node.element;
    enterScope(element);
    try {
      return super.visitMethodDeclaration(node);
    } finally {
      exitScope();
    }
  }

  Object visitMethodInvocation(MethodInvocation node) {
    SimpleIdentifier name = node.methodName;
    Element element = name.bestElement;
    if (element is MethodElement) {
      Location location = createLocation3(name);
      Relationship relationship;
      if (node.target != null) {
        relationship = IndexConstants.IS_INVOKED_BY_QUALIFIED;
      } else {
        relationship = IndexConstants.IS_INVOKED_BY_UNQUALIFIED;
      }
      recordRelationship(element, relationship, location);
    }
    if (element is FunctionElement) {
      Location location = createLocation3(name);
      recordRelationship(element, IndexConstants.IS_INVOKED_BY, location);
    }
    recordImportElementReferenceWithoutPrefix(name);
    return super.visitMethodInvocation(node);
  }

  Object visitPartDirective(PartDirective node) {
    Element element = node.element;
    Location location = createLocation3(node.uri);
    recordRelationship(element, IndexConstants.IS_REFERENCED_BY, location);
    return super.visitPartDirective(node);
  }

  Object visitPartOfDirective(PartOfDirective node) {
    Location location = createLocation3(node.libraryName);
    recordRelationship(node.element, IndexConstants.IS_REFERENCED_BY, location);
    return null;
  }

  Object visitPostfixExpression(PostfixExpression node) {
    recordOperatorReference(node.operator, node.bestElement);
    return super.visitPostfixExpression(node);
  }

  Object visitPrefixExpression(PrefixExpression node) {
    recordOperatorReference(node.operator, node.bestElement);
    return super.visitPrefixExpression(node);
  }

  Object visitSimpleIdentifier(SimpleIdentifier node) {
    Element nameElement = new NameElementImpl(node.name);
    Location location = createLocation3(node);
    // name in declaration
    if (node.inDeclarationContext()) {
      recordRelationship(nameElement, IndexConstants.IS_DEFINED_BY, location);
      return null;
    }
    // prepare information
    Element element = node.bestElement;
    // qualified name reference
    recordQualifiedMemberReference(node, element, nameElement, location);
    // stop if already handled
    if (isAlreadyHandledName(node)) {
      return null;
    }
    // record specific relations
    if (element is ClassElement || element is FunctionElement || element is FunctionTypeAliasElement || element is LabelElement || element is TypeParameterElement) {
      recordRelationship(element, IndexConstants.IS_REFERENCED_BY, location);
    } else if (element is FieldElement) {
      location = getLocationWithInitializerType(node, location);
      recordRelationship(element, IndexConstants.IS_REFERENCED_BY, location);
    } else if (element is FieldFormalParameterElement) {
      FieldFormalParameterElement fieldParameter = element;
      FieldElement field = fieldParameter.field;
      recordRelationship(field, IndexConstants.IS_REFERENCED_BY_QUALIFIED, location);
    } else if (element is PrefixElement) {
      recordImportElementReferenceWithPrefix(node);
    } else if (element is PropertyAccessorElement || element is MethodElement) {
      location = getLocationWithTypeAssignedToField(node, element, location);
      if (isQualified(node)) {
        recordRelationship(element, IndexConstants.IS_REFERENCED_BY_QUALIFIED, location);
      } else {
        recordRelationship(element, IndexConstants.IS_REFERENCED_BY_UNQUALIFIED, location);
      }
    } else if (element is ParameterElement || element is LocalVariableElement) {
      bool inGetterContext = node.inGetterContext();
      bool inSetterContext = node.inSetterContext();
      if (inGetterContext && inSetterContext) {
        recordRelationship(element, IndexConstants.IS_READ_WRITTEN_BY, location);
      } else if (inGetterContext) {
        recordRelationship(element, IndexConstants.IS_READ_BY, location);
      } else if (inSetterContext) {
        recordRelationship(element, IndexConstants.IS_WRITTEN_BY, location);
      } else {
        recordRelationship(element, IndexConstants.IS_REFERENCED_BY, location);
      }
    }
    recordImportElementReferenceWithoutPrefix(node);
    return super.visitSimpleIdentifier(node);
  }

  Object visitSuperConstructorInvocation(SuperConstructorInvocation node) {
    ConstructorElement element = node.staticElement;
    Location location;
    if (node.constructorName != null) {
      int start = node.period.offset;
      int end = node.constructorName.end;
      location = createLocation4(start, end - start);
    } else {
      int start = node.keyword.end;
      location = createLocation4(start, 0);
    }
    recordRelationship(element, IndexConstants.IS_REFERENCED_BY, location);
    return super.visitSuperConstructorInvocation(node);
  }

  Object visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    VariableDeclarationList variables = node.variables;
    for (VariableDeclaration variableDeclaration in variables.variables) {
      Element element = variableDeclaration.element;
      recordElementDefinition(element, IndexConstants.DEFINES_VARIABLE);
    }
    return super.visitTopLevelVariableDeclaration(node);
  }

  Object visitTypeParameter(TypeParameter node) {
    TypeParameterElement element = node.element;
    enterScope(element);
    try {
      return super.visitTypeParameter(node);
    } finally {
      exitScope();
    }
  }

  Object visitVariableDeclaration(VariableDeclaration node) {
    VariableElement element = node.element;
    // record declaration
    {
      SimpleIdentifier name = node.name;
      Location location = createLocation3(name);
      location = getLocationWithExpressionType(location, node.initializer);
      recordRelationship(element, IndexConstants.IS_DEFINED_BY, location);
    }
    // visit
    enterScope(element);
    try {
      return super.visitVariableDeclaration(node);
    } finally {
      exitScope();
    }
  }

  Object visitVariableDeclarationList(VariableDeclarationList node) {
    NodeList<VariableDeclaration> variables = node.variables;
    if (variables != null) {
      // use first VariableDeclaration as Element for Location(s) in type
      {
        TypeName type = node.type;
        if (type != null) {
          for (VariableDeclaration variableDeclaration in variables) {
            enterScope(variableDeclaration.element);
            try {
              type.accept(this);
            } finally {
              exitScope();
            }
            // only one iteration
            break;
          }
        }
      }
      // visit variables
      variables.accept(this);
    }
    return null;
  }

  /**
   * Record the given relationship between the given [Element] and [Location].
   */
  void recordRelationship(Element element, Relationship relationship, Location location) {
    if (element != null && location != null) {
      _store.recordRelationship(element, relationship, location);
    }
  }

  /**
   * @return the [Location] representing location of the [ASTNode].
   */
  Location createLocation3(ASTNode node) => createLocation4(node.offset, node.length);

  /**
   * @param offset the offset of the location within [Source]
   * @param length the length of the location
   * @return the [Location] representing the given offset and length within the inner-most
   *         [Element].
   */
  Location createLocation4(int offset, int length) {
    Element element = peekElement();
    return new Location(element, offset, length);
  }

  /**
   * @return the [Location] representing location of the [Token].
   */
  Location createLocation5(Token token) => createLocation4(token.offset, token.length);

  /**
   * Exit the current scope.
   */
  void exitScope() {
    _elementStack.removeFirst();
  }

  /**
   * @return `true` if given node already indexed as more interesting reference, so it should
   *         not be indexed again.
   */
  bool isAlreadyHandledName(SimpleIdentifier node) {
    ASTNode parent = node.parent;
    if (parent is MethodInvocation) {
      Element element = node.staticElement;
      if (element is MethodElement || element is FunctionElement) {
        return identical(parent.methodName, node);
      }
    }
    return false;
  }

  /**
   * Records the [Element] definition in the library and universe.
   */
  void recordElementDefinition(Element element, Relationship relationship) {
    Location location = createLocation(element);
    recordRelationship(_libraryElement, relationship, location);
    recordRelationship(IndexConstants.UNIVERSE, relationship, location);
  }

  /**
   * Records [ImportElement] reference if given [SimpleIdentifier] references some
   * top-level element and not qualified with import prefix.
   */
  void recordImportElementReferenceWithoutPrefix(SimpleIdentifier node) {
    if (isIdentifierInPrefixedIdentifier(node)) {
      return;
    }
    Element element = node.staticElement;
    ImportElement importElement = getImportElement2(_libraryElement, null, element, _importElementsMap);
    if (importElement != null) {
      Location location = createLocation4(node.offset, 0);
      recordRelationship(importElement, IndexConstants.IS_REFERENCED_BY, location);
    }
  }

  /**
   * Records [ImportElement] that declares given prefix and imports library with element used
   * with given prefix node.
   */
  void recordImportElementReferenceWithPrefix(SimpleIdentifier prefixNode) {
    IndexContributor_ImportElementInfo info = getImportElementInfo(prefixNode);
    if (info != null) {
      int offset = prefixNode.offset;
      int length = info._periodEnd - offset;
      Location location = createLocation4(offset, length);
      recordRelationship(info._element, IndexConstants.IS_REFERENCED_BY, location);
    }
  }

  /**
   * Records reference to defining [CompilationUnitElement] of the given
   * [LibraryElement].
   */
  void recordLibraryReference(UriBasedDirective node, LibraryElement library) {
    if (library != null) {
      Location location = createLocation3(node.uri);
      recordRelationship(library.definingCompilationUnit, IndexConstants.IS_REFERENCED_BY, location);
    }
  }

  /**
   * Record reference to the given operator [Element] and name.
   */
  void recordOperatorReference(Token operator, Element element) {
    // prepare location
    Location location = createLocation5(operator);
    // record name reference
    {
      String name = operator.lexeme;
      if (name == "++") {
        name = "+";
      }
      if (name == "--") {
        name = "-";
      }
      if (StringUtilities.endsWithChar(name, 0x3D) && name != "==") {
        name = name.substring(0, name.length - 1);
      }
      Element nameElement = new NameElementImpl(name);
      Relationship relationship = element != null ? IndexConstants.IS_REFERENCED_BY_QUALIFIED_RESOLVED : IndexConstants.IS_REFERENCED_BY_QUALIFIED_UNRESOLVED;
      recordRelationship(nameElement, relationship, location);
    }
    // record element reference
    if (element != null) {
      recordRelationship(element, IndexConstants.IS_INVOKED_BY_QUALIFIED, location);
    }
  }

  /**
   * Records reference if the given [SimpleIdentifier] looks like a qualified property access
   * or method invocation.
   */
  void recordQualifiedMemberReference(SimpleIdentifier node, Element element, Element nameElement, Location location) {
    if (isQualified(node)) {
      Relationship relationship = element != null ? IndexConstants.IS_REFERENCED_BY_QUALIFIED_RESOLVED : IndexConstants.IS_REFERENCED_BY_QUALIFIED_UNRESOLVED;
      recordRelationship(nameElement, relationship, location);
    }
  }

  /**
   * Records extends/implements relationships between given [ClassElement] and [Type] of
   * "superNode".
   */
  void recordSuperType(TypeName superNode, Relationship relationship) {
    if (superNode != null) {
      Identifier superName = superNode.name;
      if (superName != null) {
        Element superElement = superName.staticElement;
        recordRelationship(superElement, relationship, createLocation3(superNode));
      }
    }
  }
}

/**
 * Information about [ImportElement] and place where it is referenced using
 * [PrefixElement].
 */
class IndexContributor_ImportElementInfo {
  ImportElement _element;

  int _periodEnd = 0;
}

/**
 * Factory for [Index] and [IndexStore].
 *
 * @coverage dart.engine.index
 */
class IndexFactory {
  /**
   * @return the new instance of [Index] which uses given [IndexStore].
   */
  static Index newIndex(IndexStore store) {
    OperationQueue queue = new OperationQueue();
    OperationProcessor processor = new OperationProcessor(queue);
    return new IndexImpl(store, queue, processor);
  }

  /**
   * @return the new instance of [MemoryIndexStore].
   */
  static MemoryIndexStore newMemoryIndexStore() => new MemoryIndexStoreImpl();
}

/**
 * Instances of the [OperationQueue] represent a queue of operations against the index that
 * are waiting to be performed.
 *
 * @coverage dart.engine.index
 */
class OperationQueue {
  /**
   * The non-query operations that are waiting to be performed.
   */
  Queue<IndexOperation> _nonQueryOperations = new Queue();

  /**
   * The query operations that are waiting to be performed.
   */
  Queue<IndexOperation> _queryOperations = new Queue();

  /**
   * `true` if query operations should be returned by [dequeue] or {code false}
   * if not.
   */
  bool _processQueries = true;

  /**
   * If this queue is not empty, then remove the next operation from the head of this queue and
   * return it. If this queue is empty (see [setProcessQueries], then the behavior
   * of this method depends on the value of the argument. If the argument is less than or equal to
   * zero (<code>0</code>), then `null` will be returned immediately. If the argument is
   * greater than zero, then this method will wait until at least one operation has been added to
   * this queue or until the given amount of time has passed. If, at the end of that time, this
   * queue is empty, then `null` will be returned. If this queue is not empty, then the first
   * operation will be removed and returned.
   *
   * Note that `null` can be returned, even if a positive timeout is given.
   *
   * Note too that this method's timeout is not treated the same way as the timeout value used for
   * [Object#wait]. In particular, it is not possible to cause this method to wait for
   * an indefinite period of time.
   *
   * @param timeout the maximum number of milliseconds to wait for an operation to be available
   *          before giving up and returning `null`
   * @return the operation that was removed from the queue
   * @throws InterruptedException if the thread on which this method is running was interrupted
   *           while it was waiting for an operation to be added to the queue
   */
  IndexOperation dequeue(int timeout) {
    {
      if (_nonQueryOperations.isEmpty && (!_processQueries || _queryOperations.isEmpty)) {
        if (timeout <= 0) {
          return null;
        }
        waitForOperationAvailable(timeout);
      }
      if (!_nonQueryOperations.isEmpty) {
        return _nonQueryOperations.removeFirst();
      }
      if (_processQueries && !_queryOperations.isEmpty) {
        return _queryOperations.removeFirst();
      }
      return null;
    }
  }

  /**
   * Add the given operation to the tail of this queue.
   *
   * @param operation the operation to be added to the queue
   */
  void enqueue(IndexOperation operation) {
    {
      if (operation is RemoveSourceOperation) {
        Source source = operation.source;
        removeForSource(source, _nonQueryOperations);
        removeForSource(source, _queryOperations);
      }
      if (operation.isQuery) {
        _queryOperations.add(operation);
      } else {
        _nonQueryOperations.add(operation);
      }
      notifyOperationAvailable();
    }
  }

  /**
   * Return a list containing all of the operations that are currently on the queue. Modifying this
   * list will not affect the state of the queue.
   *
   * @return all of the operations that are currently on the queue
   */
  List<IndexOperation> get operations {
    List<IndexOperation> operations = [];
    {
      operations.addAll(_nonQueryOperations);
      operations.addAll(_queryOperations);
    }
    return operations;
  }

  /**
   * Set whether the receiver's [dequeue] method should return query operations.
   *
   * @param processQueries `true` if the receiver's [dequeue] method should
   *          return query operations or `false` if query operations should be queued but not
   *          returned by the receiver's [dequeue] method until this method is called
   *          with a value of `true`.
   */
  void set processQueries(bool processQueries) {
    {
      if (this._processQueries != processQueries) {
        this._processQueries = processQueries;
        if (processQueries && !_queryOperations.isEmpty) {
          notifyOperationAvailable();
        }
      }
    }
  }

  /**
   * Return the number of operations on the queue.
   *
   * @return the number of operations on the queue
   */
  int size() {
    {
      return _nonQueryOperations.length + _queryOperations.length;
    }
  }

  void notifyOperationAvailable() {
  }

  /**
   * Removes operations that should be removed when given [Source] is removed.
   */
  void removeForSource(Source source, Queue<IndexOperation> operations) {
    operations.removeWhere((_) => _.removeWhenSourceRemoved(source));
  }

  void waitForOperationAvailable(int timeout) {
  }
}

/**
 * Special [Element] which is used to index references to the name without specifying concrete
 * kind of this name - field, method or something else.
 *
 * @coverage dart.engine.index
 */
class NameElementImpl extends ElementImpl {
  NameElementImpl(String name) : super.con2("name:${name}", -1);

  accept(ElementVisitor visitor) => null;

  ElementKind get kind => ElementKind.NAME;
}

/**
 * Visits resolved [CompilationUnit] and adds Angular specific relationships into
 * [IndexStore].
 *
 * @coverage dart.engine.index
 */
class AngularDartIndexContributor extends GeneralizingASTVisitor<Object> {
  IndexStore _store;

  AngularDartIndexContributor(IndexStore store) {
    this._store = store;
  }

  Object visitClassDeclaration(ClassDeclaration node) {
    ClassElement classElement = node.element;
    if (classElement != null) {
      List<ToolkitObjectElement> toolkitObjects = classElement.toolkitObjects;
      for (ToolkitObjectElement object in toolkitObjects) {
        if (object is AngularComponentElement) {
          indexComponent(object);
        }
        if (object is AngularDirectiveElement) {
          AngularDirectiveElement directive = object;
          indexDirective(directive);
        }
      }
    }
    // stop visiting
    return null;
  }

  Object visitCompilationUnitMember(CompilationUnitMember node) => null;

  void indexComponent(AngularComponentElement component) {
    indexProperties(component.properties);
  }

  void indexDirective(AngularDirectiveElement directive) {
    indexProperties(directive.properties);
  }

  void indexProperties(List<AngularPropertyElement> properties) {
    for (AngularPropertyElement property in properties) {
      FieldElement field = property.field;
      if (field != null) {
        int offset = property.fieldNameOffset;
        int length = field.name.length;
        Location location = new Location(property, offset, length);
        // getter reference
        if (property.propertyKind.callsGetter()) {
          PropertyAccessorElement getter = field.getter;
          if (getter != null) {
            _store.recordRelationship(getter, IndexConstants.IS_REFERENCED_BY_QUALIFIED, location);
          }
        }
        // setter reference
        if (property.propertyKind.callsSetter()) {
          PropertyAccessorElement setter = field.setter;
          if (setter != null) {
            _store.recordRelationship(setter, IndexConstants.IS_REFERENCED_BY_QUALIFIED, location);
          }
        }
      }
    }
  }
}

/**
 * Instances of the [RemoveContextOperation] implement an operation that removes from the
 * index any data based on the specified [AnalysisContext].
 *
 * @coverage dart.engine.index
 */
class RemoveContextOperation implements IndexOperation {
  /**
   * The index store against which this operation is being run.
   */
  IndexStore _indexStore;

  /**
   * The context being removed.
   */
  final AnalysisContext context;

  /**
   * Initialize a newly created operation that will remove the specified resource.
   *
   * @param indexStore the index store against which this operation is being run
   * @param context the [AnalysisContext] to remove
   */
  RemoveContextOperation(IndexStore indexStore, this.context) {
    this._indexStore = indexStore;
  }

  bool get isQuery => false;

  void performOperation() {
    {
      _indexStore.removeContext(context);
    }
  }

  bool removeWhenSourceRemoved(Source source) => false;

  String toString() => "RemoveContext(${context})";
}

/**
 * Instances of the [IndexHtmlUnitOperation] implement an operation that adds data to the
 * index based on the resolved [HtmlUnit].
 *
 * @coverage dart.engine.index
 */
class IndexHtmlUnitOperation implements IndexOperation {
  /**
   * The index store against which this operation is being run.
   */
  IndexStore _indexStore;

  /**
   * The context in which [HtmlUnit] was resolved.
   */
  AnalysisContext _context;

  /**
   * The [HtmlUnit] being indexed.
   */
  final ht.HtmlUnit unit;

  /**
   * The element of the [HtmlUnit] being indexed.
   */
  HtmlElement _htmlElement;

  /**
   * The source being indexed.
   */
  Source _source;

  /**
   * Initialize a newly created operation that will index the specified [HtmlUnit].
   *
   * @param indexStore the index store against which this operation is being run
   * @param context the context in which [HtmlUnit] was resolved
   * @param unit the fully resolved [HtmlUnit]
   */
  IndexHtmlUnitOperation(IndexStore indexStore, AnalysisContext context, this.unit) {
    this._indexStore = indexStore;
    this._context = context;
    this._htmlElement = unit.element;
    this._source = _htmlElement.source;
  }

  /**
   * @return the [Source] to be indexed.
   */
  Source get source => _source;

  bool get isQuery => false;

  void performOperation() {
    {
      try {
        bool mayIndex = _indexStore.aboutToIndex2(_context, _source);
        if (!mayIndex) {
          return;
        }
        AngularHtmlIndexContributor contributor = new AngularHtmlIndexContributor(_indexStore);
        unit.accept(contributor);
      } catch (exception) {
        AnalysisEngine.instance.logger.logError2("Could not index ${unit.element.location}", exception);
      }
    }
  }

  bool removeWhenSourceRemoved(Source source) => this._source == source;

  String toString() => "IndexHtmlUnitOperation(${_source.fullName})";
}

/**
 * Instances of the class <code>Location</code> represent a location related to an element. The
 * location is expressed as an offset and length, but the offset is relative to the resource
 * containing the element rather than the start of the element within that resource.
 *
 * @coverage dart.engine.index
 */
class Location {
  /**
   * An empty array of locations.
   */
  static List<Location> EMPTY_ARRAY = new List<Location>(0);

  /**
   * The element containing this location.
   */
  final Element element;

  /**
   * The offset of this location within the resource containing the element.
   */
  final int offset;

  /**
   * The length of this location.
   */
  final int length;

  /**
   * Internal field used to hold a key that is referenced at this location.
   */
  Object internalKey;

  /**
   * Initialize a newly create location to be relative to the given element at the given offset with
   * the given length.
   *
   * @param element the [Element] containing this location
   * @param offset the offset of this location within the resource containing the element
   * @param length the length of this location
   */
  Location(this.element, this.offset, this.length) {
    if (element == null) {
      throw new IllegalArgumentException("element location cannot be null");
    }
  }

  Location clone() => new Location(element, offset, length);

  String toString() => "[${offset} - ${(offset + length)}) in ${element}";
}

/**
 * [IndexStore] which keeps all information in memory, but can write it to stream and read
 * later.
 *
 * @coverage dart.engine.index
 */
abstract class MemoryIndexStore implements IndexStore {
}

/**
 * Instances of the [GetRelationshipsOperation] implement an operation used to access the
 * locations that have a specified relationship with a specified element.
 *
 * @coverage dart.engine.index
 */
class GetRelationshipsOperation implements IndexOperation {
  IndexStore _indexStore;

  final Element element;

  final Relationship relationship;

  final RelationshipCallback callback;

  /**
   * Initialize a newly created operation that will access the locations that have a specified
   * relationship with a specified element.
   */
  GetRelationshipsOperation(IndexStore indexStore, this.element, this.relationship, this.callback) {
    this._indexStore = indexStore;
  }

  bool get isQuery => true;

  void performOperation() {
    List<Location> locations;
    {
      locations = _indexStore.getRelationships(element, relationship);
    }
    callback.hasRelationships(element, relationship, locations);
  }

  bool removeWhenSourceRemoved(Source source) => false;

  String toString() => "GetRelationships(${element}, ${relationship})";
}

/**
 * [Location] with attached data.
 */
class LocationWithData<D> extends Location {
  final D data;

  LocationWithData.con1(Location location, this.data) : super(location.element, location.offset, location.length);

  LocationWithData.con2(Element element, int offset, int length, this.data) : super(element, offset, length);

  Location clone() => new LocationWithData<D>.con2(element, offset, length, data);
}

/**
 * The interface <code>RelationshipCallback</code> defines the behavior of objects that are invoked
 * with the results of a query about a given relationship.
 *
 * @coverage dart.engine.index
 */
abstract class RelationshipCallback {
  /**
   * This method is invoked when the locations that have a specified relationship with a specified
   * element are available. For example, if the element is a field and the relationship is the
   * is-referenced-by relationship, then this method will be invoked with each location at which the
   * field is referenced.
   *
   * @param element the [Element] that has the relationship with the locations
   * @param relationship the relationship between the given element and the locations
   * @param locations the locations that were found
   */
  void hasRelationships(Element element, Relationship relationship, List<Location> locations);
}