//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2019-2020 Apple Inc. and the SwiftServiceDiscovery project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftServiceDiscovery project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#include <stdbool.h>
#include <stdint.h>

struct c_sd_atomic_long {
    _Atomic long value;
};
struct c_sd_atomic_long * _Nonnull c_sd_atomic_long_create(long value);
bool c_sd_atomic_long_compare_and_exchange(struct c_sd_atomic_long * _Nonnull atomic, long expected, long desired);
long c_sd_atomic_long_add(struct c_sd_atomic_long * _Nonnull atomic, long value);
long c_sd_atomic_long_sub(struct c_sd_atomic_long * _Nonnull atomic, long value);
long c_sd_atomic_long_load(struct c_sd_atomic_long * _Nonnull atomic);
void c_sd_atomic_long_store(struct c_sd_atomic_long * _Nonnull atomic, long value);

struct c_sd_atomic_bool {
    _Atomic bool value;
};
struct c_sd_atomic_bool * _Nonnull c_sd_atomic_bool_create(bool value);
bool c_sd_atomic_bool_compare_and_exchange(struct c_sd_atomic_bool * _Nonnull atomic, bool expected, bool desired);
bool c_sd_atomic_bool_add(struct c_sd_atomic_bool * _Nonnull atomic, bool value);
bool c_sd_atomic_bool_sub(struct c_sd_atomic_bool * _Nonnull atomic, bool value);
bool c_sd_atomic_bool_load(struct c_sd_atomic_bool * _Nonnull atomic);
void c_sd_atomic_bool_store(struct c_sd_atomic_bool * _Nonnull atomic, bool value);
