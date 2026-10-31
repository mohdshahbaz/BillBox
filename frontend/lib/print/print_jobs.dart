import 'dart:typed_data';
import 'package:flutter/foundation.dart';

enum JobStatus { printing, done, failed }

class PrintJob {
  final int id;
  final String title, printer, layout;
  final int copies;
  final DateTime time = DateTime.now();
  final Uint8List bytes; // kept so a failed or lost job can be sent again with one click
  JobStatus status = JobStatus.printing;
  String? error;
  PrintJob(this.id, this.title, this.printer, this.layout, this.copies, this.bytes);
}

/// In-app print job list for this session: status, error text, reprint.
class PrintJobs extends ChangeNotifier {
  PrintJobs._();
  static final instance = PrintJobs._();
  final jobs = <PrintJob>[];
  int _next = 1;

  PrintJob add(String title, String printer, String layout, int copies, Uint8List bytes) {
    final j = PrintJob(_next++, title, printer, layout, copies, bytes);
    jobs.insert(0, j);
    if (jobs.length > 50) jobs.removeLast();
    notifyListeners();
    return j;
  }

  void update(PrintJob j, JobStatus s, [String? error]) {
    j.status = s;
    j.error = error;
    notifyListeners();
  }

  void remove(PrintJob j) {
    jobs.remove(j);
    notifyListeners();
  }
}
