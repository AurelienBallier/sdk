// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * A representation of the contents of an instrumentation log.
 */
library analysis_server.tool.instrumentation.log;

import 'dart:collection';
import 'dart:convert';

import 'package:analyzer/instrumentation/instrumentation.dart';

/**
 * A range of log entries, represented by the index of the first and last
 * entries in the range.
 */
class EntryRange {
  /**
   * The index of the first entry in the range.
   */
  int firstIndex;

  /**
   * The index of the first entry in the range.
   */
  int lastIndex;

  /**
   * Initialize a newly created range to represent the entries between the
   * [firstIndex] and the [lastIndex], inclusive.
   */
  EntryRange(this.firstIndex, this.lastIndex);
}

/**
 * A log entry representing an Err entry.
 */
class ErrorEntry extends GenericEntry {
  /**
   * Initialize a newly created log entry.
   */
  ErrorEntry(
      int index, int timeStamp, String entryKind, List<String> components)
      : super(index, timeStamp, entryKind, components);
}

/**
 * A log entry representing an Ex entry.
 */
class ExceptionEntry extends GenericEntry {
  /**
   * Initialize a newly created log entry.
   */
  ExceptionEntry(
      int index, int timeStamp, String entryKind, List<String> components)
      : super(index, timeStamp, entryKind, components);
}

/**
 * A representation of a generic log entry.
 */
class GenericEntry extends LogEntry {
  /**
   * The kind of the log entry.
   */
  String entryKind;

  /**
   * The components in the entry that follow the time stamp and entry kind.
   */
  List<String> components;

  /**
   * Initialize a newly created generic log entry to have the given [timeStamp],
   * [entryKind] and list of [components]
   */
  GenericEntry(int index, int timeStamp, this.entryKind, this.components)
      : super(index, timeStamp);

  @override
  String get kind => entryKind;

  @override
  void _appendDetails(StringBuffer buffer) {
    super._appendDetails(buffer);
    for (String component in components) {
      buffer.write(component);
      buffer.write('<br>');
    }
  }
}

/**
 * A representation of an instrumentation log.
 */
class InstrumentationLog {
  /**
   * The paths of the log files containing the entries.
   */
  List<String> logFilePaths;

  /**
   * The entries in the instrumentation log.
   */
  List<LogEntry> logEntries;

  /**
   * The entries in the instrumentation log that are not instances of
   * [TaskEntry].
   */
  List<LogEntry> nonTaskEntries;

  /**
   * A table mapping entries that are paired with another entry to the entry
   * with which they are paired.
   */
  Map<LogEntry, LogEntry> _pairedEntries = new HashMap<LogEntry, LogEntry>();

  /**
   * A table mapping the id's of requests to the entry representing the request.
   */
  Map<String, RequestEntry> _requestMap = new HashMap<String, RequestEntry>();

  /**
   * A table mapping the id's of responses to the entry representing the
   * response.
   */
  Map<String, ResponseEntry> _responseMap =
      new HashMap<String, ResponseEntry>();

  /**
   * A table mapping the ids of completion events to the events with those ids.
   */
  Map<String, List<NotificationEntry>> _completionMap =
      new HashMap<String, List<NotificationEntry>>();

  /**
   * The ranges of entries that are between analysis start and analysis end
   * notifications.
   */
  List<EntryRange> analysisRanges;

  /**
   * Initialize a newly created instrumentation log by parsing each of the lines
   * in the [logContent] into a separate entry. The log contents should be the
   * contents of the files whose paths are in the given list of [logFilePaths].
   */
  InstrumentationLog(this.logFilePaths, List<String> logContent) {
    _parseLogContent(logContent);
  }

  /**
   * Return a list of the completion events associated with the given [id].
   */
  List<NotificationEntry> completionEventsWithId(String id) =>
      _completionMap[id];

  /**
   * Return the entry that is paired with the given [entry], or `null` if there
   * is no entry paired with it.
   */
  LogEntry pairedEntry(LogEntry entry) => _pairedEntries[entry];

  /**
   * Return the response that corresponds to the given request.
   */
  RequestEntry requestFor(ResponseEntry entry) => _requestMap[entry.id];

  /**
   * Return the response that corresponds to the given request.
   */
  ResponseEntry responseFor(RequestEntry entry) => _responseMap[entry.id];

  /**
   * Return a list containing all of the task entries between the start of
   * analysis notification at the given [startIndex] and the matching end of
   * analysis notification (or the end of the log if the log does not contain a
   * corresponding end notification.
   */
  List<TaskEntry> taskEntriesFor(int startIndex) {
    List<TaskEntry> taskEntries = <TaskEntry>[];
    NotificationEntry startEntry = nonTaskEntries[startIndex];
    LogEntry endEntry = pairedEntry(startEntry);
    int lastIndex = endEntry == null ? logEntries.length : endEntry.index;
    for (int i = startEntry.index + 1; i < lastIndex; i++) {
      LogEntry entry = logEntries[i];
      if (entry is TaskEntry) {
        taskEntries.add(entry);
      }
    }
    return taskEntries;
  }

  /**
   * Merge any multi-line entries into a single line so that every element in
   * the given [logContent] is a single entry.
   */
  void _mergeEntries(List<String> logContent) {
    bool isStartOfEntry(String line) {
      return line.startsWith(LogEntry.entryRegExp);
    }

    String merge(String line, List<String> extraLines) {
      StringBuffer buffer = new StringBuffer();
      buffer.writeln(line);
      for (String extraLine in extraLines) {
        buffer.writeln(extraLine);
      }
      return buffer.toString();
    }

    List<String> extraLines = <String>[];
    for (int i = logContent.length - 1; i >= 0; i--) {
      String line = logContent[i];
      if (isStartOfEntry(line)) {
        if (extraLines.isNotEmpty) {
          logContent[i] = merge(line, extraLines);
        }
      } else {
        logContent.removeAt(i);
        extraLines.insert(0, line);
      }
    }
    if (extraLines.isNotEmpty) {
      throw new StateError(
          '${extraLines.length} non-entry lines before any entry');
    }
  }

  /**
   * Parse the given [logContent] into a list of log entries.
   */
  void _parseLogContent(List<String> logContent) {
    _mergeEntries(logContent);
    logEntries = <LogEntry>[];
    nonTaskEntries = <LogEntry>[];
    analysisRanges = <EntryRange>[];
    NotificationEntry analysisStartEntry = null;
    int analysisStartIndex = -1;
    NotificationEntry pubStartEntry = null;
    for (String line in logContent) {
      LogEntry entry = new LogEntry.from(logEntries.length, line);
      if (entry != null) {
        logEntries.add(entry);
        if (entry is! TaskEntry) {
          nonTaskEntries.add(entry);
        }
        if (entry is RequestEntry) {
          _requestMap[entry.id] = entry;
        } else if (entry is ResponseEntry) {
          _responseMap[entry.id] = entry;
          RequestEntry request = _requestMap[entry.id];
          _pairedEntries[entry] = request;
          _pairedEntries[request] = entry;
        } else if (entry is NotificationEntry) {
          if (entry.isServerStatus) {
            var analysisStatus = entry.param('analysis');
            if (analysisStatus is Map) {
              if (analysisStatus['isAnalyzing']) {
                if (analysisStartEntry != null) {
                  analysisStartEntry.recordProblem(
                      'Analysis started without being terminated.');
                }
                analysisStartEntry = entry;
                analysisStartIndex = logEntries.length - 1;
              } else {
                if (analysisStartEntry == null) {
                  entry.recordProblem(
                      'Analysis terminated without being started.');
                } else {
                  int analysisEnd = logEntries.length - 1;
                  analysisRanges
                      .add(new EntryRange(analysisStartIndex, analysisEnd));
                  _pairedEntries[entry] = analysisStartEntry;
                  _pairedEntries[analysisStartEntry] = entry;
                  analysisStartEntry = null;
                  analysisStartIndex = -1;
                }
              }
            }
            var pubStatus = entry.param('pub');
            if (pubStatus is Map) {
              if (pubStatus['isListingPackageDirs']) {
                if (pubStartEntry != null) {
                  pubStartEntry.recordProblem(
                      'Pub started without previous being terminated.');
                }
                pubStartEntry = entry;
              } else {
                if (pubStartEntry == null) {
                  entry.recordProblem('Pub terminated without being started.');
                } else {
                  _pairedEntries[entry] = pubStartEntry;
                  _pairedEntries[pubStartEntry] = entry;
                  pubStartEntry = null;
                }
              }
            }
          } else if (entry.event == 'completion.results') {
            String id = entry.param('id');
            if (id != null) {
              _completionMap
                  .putIfAbsent(id, () => new List<NotificationEntry>())
                  .add(entry);
            }
          }
        }
      }
    }
    if (analysisStartEntry != null) {
      analysisStartEntry
          .recordProblem('Analysis started without being terminated.');
    }
    if (pubStartEntry != null) {
      pubStartEntry
          .recordProblem('Pub started without previous being terminated.');
    }
  }
}

/**
 * A log entry that has a single JSON encoded component following the time stamp
 * and entry kind.
 */
abstract class JsonBasedEntry extends LogEntry {
  /**
   * The HTML string used to indent text when formatting the JSON [data].
   */
  static const String singleIndent = '&nbsp;&nbsp;&nbsp;';

  /**
   * The decoded form of the JSON encoded component.
   */
  final Map data;

  /**
   * Initialize a newly created log entry to have the given [timeStamp] and
   * [data].
   */
  JsonBasedEntry(int index, int timeStamp, this.data) : super(index, timeStamp);

  @override
  void _appendDetails(StringBuffer buffer) {
    super._appendDetails(buffer);
    _format(buffer, '', data);
  }

  /**
   * Encode any character in the given [string] that would prevent source code
   * from being displayed correctly: end of line markers and spaces.
   */
  String _encodeSourceCode(String string) {
    // TODO(brianwilkerson) This method isn't working completely. Some source
    // code produces an error of
    // "log?start=3175:261 Uncaught SyntaxError: missing ) after argument list"
    // in the sample log I was using.
    StringBuffer buffer = new StringBuffer();
    int length = string.length;
    int index = 0;
    while (index < length) {
      int char = string.codeUnitAt(index);
      index++;
      // TODO(brianwilkerson) Handle tabs and other special characters.
      if (char == '\r'.codeUnitAt(0)) {
        if (index < length && string.codeUnitAt(index) == '\n'.codeUnitAt(0)) {
          index++;
        }
        buffer.write('<br>');
      } else if (char == '\n'.codeUnitAt(0)) {
        buffer.write('<br>');
      } else if (char == ' '.codeUnitAt(0)) {
        // Encode all spaces in order to accurately reproduce the original
        // source code when displaying it.
        buffer.write('&nbsp;');
      } else {
        buffer.writeCharCode(char);
      }
    }
    return buffer.toString();
  }

  /**
   * Write an HTML representation the given JSON [object] to the given [buffer],
   * using the given [indent] to make the output more readable.
   */
  void _format(StringBuffer buffer, String indent, Object object) {
    if (object is String) {
      buffer.write('"');
      buffer.write(_encodeSourceCode(object));
      buffer.write('"');
    } else if (object is int || object is bool) {
      buffer.write(object);
    } else if (object is Map) {
      buffer.write('{<br>');
      object.forEach((Object key, Object value) {
        String newIndent = indent + singleIndent;
        buffer.write(newIndent);
        _format(buffer, newIndent, key);
        buffer.write(' : ');
        _format(buffer, newIndent, value);
        buffer.write('<br>');
      });
      buffer.write(indent);
      buffer.write('}');
    } else if (object is List) {
      buffer.write('[<br>');
      object.forEach((Object element) {
        String newIndent = indent + singleIndent;
        buffer.write(newIndent);
        _format(buffer, newIndent, element);
        buffer.write('<br>');
      });
      buffer.write(indent);
      buffer.write(']');
    }
  }
}

/**
 * A single entry in an instrumentation log.
 */
abstract class LogEntry {
  /**
   * The character used to separate fields within an entry.
   */
  static final int fieldSeparator = ':'.codeUnitAt(0);

  /**
   * A regular expression that will match the beginning of a valid log entry.
   */
  static final RegExp entryRegExp = new RegExp('[0-9]+\\:');

  /**
   * A table mapping kinds to the names of those kinds.
   */
  static final Map<String, String> kindMap = {
    'Err': 'Error',
    'Ex': 'Exception',
    'Log': 'Log message',
    'Noti': 'Notification',
    'Read': 'Read file',
    'Req': 'Request',
    'Res': 'Response',
    'Perf': 'Performance data',
    'SPResult': 'Subprocess result',
    'SPStart': 'Subprocess start',
    'Task': 'Task',
    'Ver': 'Version information',
    'Watch': 'Watch event',
  };

  /**
   * The index of this entry in the log file.
   */
  final int index;

  /**
   * The time at which the entry occurred.
   */
  final int timeStamp;

  /**
   * A list containing the descriptions of problems that were found while
   * processing the log file, or `null` if no problems were found.
   */
  List<String> _problems = null;

  /**
   * Initialize a newly created log entry with the given [timeStamp].
   */
  LogEntry(this.index, this.timeStamp);

  /**
   * Create a log entry from the given encoded form of the [entry].
   */
  factory LogEntry.from(int index, String entry) {
    if (entry.isEmpty) {
      return null;
    }
    List<String> components = _parseComponents(entry);
    int timeStamp;
    try {
      timeStamp = int.parse(components[0]);
    } catch (exception) {
      print('Invalid time stamp in "${components[0]}"; entry = "$entry"');
      return null;
    }
    String entryKind = components[1];
    if (entryKind == InstrumentationService.TAG_ANALYSIS_TASK) {
      return new TaskEntry(index, timeStamp, components[2], components[3]);
    } else if (entryKind == InstrumentationService.TAG_ERROR) {
      return new ErrorEntry(index, timeStamp, entryKind, components.sublist(2));
    } else if (entryKind == InstrumentationService.TAG_EXCEPTION) {
      return new ExceptionEntry(
          index, timeStamp, entryKind, components.sublist(2));
    } else if (entryKind == InstrumentationService.TAG_FILE_READ) {
      // Fall through
    } else if (entryKind == InstrumentationService.TAG_LOG_ENTRY) {
      // Fall through
    } else if (entryKind == InstrumentationService.TAG_NOTIFICATION) {
      Map requestData = JSON.decode(components[2]);
      return new NotificationEntry(index, timeStamp, requestData);
    } else if (entryKind == InstrumentationService.TAG_PERFORMANCE) {
      // Fall through
    } else if (entryKind == InstrumentationService.TAG_REQUEST) {
      Map requestData = JSON.decode(components[2]);
      return new RequestEntry(index, timeStamp, requestData);
    } else if (entryKind == InstrumentationService.TAG_RESPONSE) {
      Map responseData = JSON.decode(components[2]);
      return new ResponseEntry(index, timeStamp, responseData);
    } else if (entryKind == InstrumentationService.TAG_SUBPROCESS_START) {
      // Fall through
    } else if (entryKind == InstrumentationService.TAG_SUBPROCESS_RESULT) {
      // Fall through
    } else if (entryKind == InstrumentationService.TAG_VERSION) {
      // Fall through
    } else if (entryKind == InstrumentationService.TAG_WATCH_EVENT) {
      // Fall through
    }
    return new GenericEntry(index, timeStamp, entryKind, components.sublist(2));
  }

  /**
   * Return `true` if any problems were found while processing the log file.
   */
  bool get hasProblems => _problems != null;

  /**
   * Return the value of the component used to indicate the kind of the entry.
   * This is the abbreviation recorded in the entry.
   */
  String get kind;

  /**
   * Return a human-readable representation of the kind of this entry.
   */
  String get kindName => kindMap[kind] ?? kind;

  /**
   * Return a list containing the descriptions of problems that were found while
   * processing the log file, or `null` if no problems were found.
   */
  List<String> get problems => _problems;

  /**
   * Return a date that is equivalent to the [timeStamp].
   */
  DateTime get toTime => new DateTime.fromMillisecondsSinceEpoch(timeStamp);

  /**
   * Return an HTML representation of the details of the entry.
   */
  String details() {
    StringBuffer buffer = new StringBuffer();
    _appendDetails(buffer);
    return buffer.toString();
  }

  /**
   * Record that the given [problem] was found while processing the log file.
   */
  void recordProblem(String problem) {
    _problems ??= <String>[];
    _problems.add(problem);
  }

  /**
   * Append details related to this entry to the given [buffer].
   */
  void _appendDetails(StringBuffer buffer) {
    if (_problems != null) {
      for (String problem in _problems) {
        buffer.write('<p><span class="error">$problem</span></p>');
      }
    }
  }

  /**
   * Parse the given encoded form of the [entry] into a list of components. The
   * first component is always the time stamp for when the entry was generated.
   * The second component is always the kind of the entry. The remaining
   * components depend on the kind of the entry. Return the components that were
   * parsed.
   */
  static List<String> _parseComponents(String entry) {
    List<String> components = <String>[];
    StringBuffer component = new StringBuffer();
    int length = entry.length;
    for (int i = 0; i < length; i++) {
      int char = entry.codeUnitAt(i);
      if (char == fieldSeparator) {
        if (entry.codeUnitAt(i + 1) == fieldSeparator) {
          component.write(':');
          i++;
        } else {
          components.add(component.toString());
          component.clear();
        }
      } else {
        component.writeCharCode(char);
      }
    }
    components.add(component.toString());
    return components;
  }
}

/**
 * A log entry representing a notification that was sent from the server to the
 * client.
 */
class NotificationEntry extends JsonBasedEntry {
  /**
   * Initialize a newly created response to have the given [timeStamp] and
   * [notificationData].
   */
  NotificationEntry(int index, int timeStamp, Map notificationData)
      : super(index, timeStamp, notificationData);

  /**
   * Return the event field of the request.
   */
  String get event => data['event'];

  /**
   * Return `true` if this is a server status notification.
   */
  bool get isServerStatus => event == 'server.status';

  @override
  String get kind => 'Noti';

  /**
   * Return the value of the parameter with the given [parameterName], or `null`
   * if there is no such parameter.
   */
  dynamic param(String parameterName) {
    var parameters = data['params'];
    if (parameters is Map) {
      return parameters[parameterName];
    }
    return null;
  }
}

/**
 * A log entry representing a request that was sent from the client to the
 * server.
 */
class RequestEntry extends JsonBasedEntry {
  /**
   * Initialize a newly created response to have the given [timeStamp] and
   * [requestData].
   */
  RequestEntry(int index, int timeStamp, Map requestData)
      : super(index, timeStamp, requestData);

  /**
   * Return the clientRequestTime field of the request.
   */
  int get clientRequestTime => data['clientRequestTime'];

  /**
   * Return the id field of the request.
   */
  String get id => data['id'];

  @override
  String get kind => 'Req';

  /**
   * Return the method field of the request.
   */
  String get method => data['method'];

  /**
   * Return the value of the parameter with the given [parameterName], or `null`
   * if there is no such parameter.
   */
  dynamic param(String parameterName) {
    var parameters = data['params'];
    if (parameters is Map) {
      return parameters[parameterName];
    }
    return null;
  }
}

/**
 * A log entry representing a response that was sent from the server to the
 * client.
 */
class ResponseEntry extends JsonBasedEntry {
  /**
   * Initialize a newly created response to have the given [timeStamp] and
   * [responseData].
   */
  ResponseEntry(int index, int timeStamp, Map responseData)
      : super(index, timeStamp, responseData);

  /**
   * Return the id field of the response.
   */
  String get id => data['id'];

  @override
  String get kind => 'Res';

  /**
   * Return the value of the result with the given [resultName], or `null`  if
   * there is no such result.
   */
  dynamic result(String resultName) {
    var results = data['result'];
    if (results is Map) {
      return results[resultName];
    }
    return null;
  }
}

class TaskEntry extends LogEntry {
  /**
   * The path to the directory at the root of the context in which analysis was
   * being performed.
   */
  final String context;

  /**
   * A description of the task that was performed.
   */
  final String description;

  /**
   * The name of the class implementing the task.
   */
  String _taskName = null;

  /**
   * The description of the target of the task.
   */
  String _target = null;

  /**
   * Initialize a newly created entry with the given [index] and [timeStamp] to
   * represent the execution of an analysis task in the given [context] that is
   * described by the given [description].
   */
  TaskEntry(int index, int timeStamp, this.context, this.description)
      : super(index, timeStamp);

  @override
  String get kind => 'Task';

  /**
   * Return the description of the target of the task.
   */
  String get target {
    if (_target == null) {
      _splitDescription();
    }
    return _target;
  }

  /**
   * Return the name of the class implementing the task.
   */
  String get taskName {
    if (_taskName == null) {
      _splitDescription();
    }
    return _taskName;
  }

  @override
  void _appendDetails(StringBuffer buffer) {
    super._appendDetails(buffer);
    buffer.write('<span class="label">Context:</span> ');
    buffer.write(context);
    buffer.write('<br><span class="label">Description: </span> ');
    buffer.write(description);
  }

  /**
   * Split the description to get the task name and target description.
   */
  void _splitDescription() {
    int index = description.indexOf(' ');
    if (index < 0) {
      _taskName = '';
    } else {
      _taskName = description.substring(0, index);
    }
    index = description.lastIndexOf(' ');
    _target = description.substring(index + 1);
    int slash = context.lastIndexOf('/');
    if (slash < 0) {
      slash = context.lastIndexOf('\\');
    }
    if (slash >= 0) {
      String prefix = context.substring(0, slash);
      _target = _target.replaceAll(prefix, '...');
    }
  }
}