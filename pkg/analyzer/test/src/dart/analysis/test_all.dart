// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library analyzer.test.src.dart.analysis.test_all;

import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'byte_store_test.dart' as byte_store;
import 'driver_test.dart' as driver;

/// Utility for manually running all tests.
main() {
  defineReflectiveSuite(() {
    byte_store.main();
    driver.main();
  }, name: 'analysis');
}
