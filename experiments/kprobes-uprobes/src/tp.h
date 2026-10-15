/* tp.h: an LTTng-UST tracepoint provider "tracelab" with one event, request. */
#undef LTTNG_UST_TRACEPOINT_PROVIDER
#define LTTNG_UST_TRACEPOINT_PROVIDER tracelab
#undef LTTNG_UST_TRACEPOINT_INCLUDE
#define LTTNG_UST_TRACEPOINT_INCLUDE "./tp.h"
#if !defined(TP_H) || defined(LTTNG_UST_TRACEPOINT_HEADER_MULTI_READ)
#define TP_H
#include <lttng/tracepoint.h>

LTTNG_UST_TRACEPOINT_EVENT(tracelab, request,
	LTTNG_UST_TP_ARGS(int, id),
	LTTNG_UST_TP_FIELDS(lttng_ust_field_integer(int, id, id))
)
#endif
#include <lttng/tracepoint-event.h>
