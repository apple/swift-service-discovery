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

#include <CSDAtomics.h>

#include <stdlib.h>
#include <stdatomic.h>

struct c_sd_atomic_long *c_sd_atomic_long_create(long value) {
    struct c_sd_atomic_long *wrapper = malloc(sizeof(*wrapper));
    atomic_init(&wrapper->value, value);
    return wrapper;
}
bool c_sd_atomic_long_compare_and_exchange(struct c_sd_atomic_long *wrapper, long expected, long desired) {
    long expected_copy = expected;
    return atomic_compare_exchange_strong(&wrapper->value, &expected_copy, desired);
}
long c_sd_atomic_long_add(struct c_sd_atomic_long *wrapper, long value) {
    return atomic_fetch_add_explicit(&wrapper->value, value, memory_order_relaxed);
}
long c_sd_atomic_long_sub(struct c_sd_atomic_long *wrapper, long value) {
    return atomic_fetch_sub_explicit(&wrapper->value, value, memory_order_relaxed);
}
long c_sd_atomic_long_load(struct c_sd_atomic_long *wrapper) {
    return atomic_load_explicit(&wrapper->value, memory_order_relaxed);
}
void c_sd_atomic_long_store(struct c_sd_atomic_long *wrapper, long value) {
    atomic_store_explicit(&wrapper->value, value, memory_order_relaxed);
}

struct c_sd_atomic_bool *c_sd_atomic_bool_create(bool value) {
    struct c_sd_atomic_bool *wrapper = malloc(sizeof(*wrapper));
    atomic_init(&wrapper->value, value);
    return wrapper;
}
bool c_sd_atomic_bool_compare_and_exchange(struct c_sd_atomic_bool *wrapper, bool expected, bool desired) {
    bool expected_copy = expected;
    return atomic_compare_exchange_strong(&wrapper->value, &expected_copy, desired);
}
bool c_sd_atomic_bool_add(struct c_sd_atomic_bool *wrapper, bool value) {
    return atomic_fetch_add_explicit(&wrapper->value, value, memory_order_relaxed);
}
bool c_sd_atomic_bool_sub(struct c_sd_atomic_bool *wrapper, bool value) {
    return atomic_fetch_sub_explicit(&wrapper->value, value, memory_order_relaxed);
}
bool c_sd_atomic_bool_load(struct c_sd_atomic_bool *wrapper) {
    return atomic_load_explicit(&wrapper->value, memory_order_relaxed);
}
void c_sd_atomic_bool_store(struct c_sd_atomic_bool *wrapper, bool value) {
    atomic_store_explicit(&wrapper->value, value, memory_order_relaxed);
}
