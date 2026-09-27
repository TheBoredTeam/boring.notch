#pragma once
#include <stddef.h>
#include <stdint.h>

// Main-thread-only ABI. Context belongs to the host; extension must return it unchanged.
typedef void (*BNExtensionCommand)(void *context, const char *command, double value);
void *bn_extension_create_v1(void *context, BNExtensionCommand command);
void bn_extension_destroy_v1(void *instance);
void bn_extension_update_v1(void *instance, const uint8_t *json, intptr_t byte_count);
void bn_extension_event_v1(void *instance, const char *event);
// Borrowed NSViewController pointer, valid until destroy. Host retains while displayed.
void *bn_extension_settings_v1(void *instance);
