#include <stddef.h>
#include <string.h>

struct antaios_static_symbol {
    const char *name;
    void *address;
};

extern const struct antaios_static_symbol antaios_static_symbols[];
extern const size_t antaios_static_symbol_count;

static _Thread_local const char *antaios_static_dlerror;

void *dlopen(const char *filename, int flags)
{
    (void)filename;
    (void)flags;
    antaios_static_dlerror = NULL;
    return (void *)1;
}

void *dlsym(void *handle, const char *name)
{
    size_t index;

    (void)handle;
    for (index = 0; index < antaios_static_symbol_count; ++index) {
        if (strcmp(name, antaios_static_symbols[index].name) == 0) {
            antaios_static_dlerror = NULL;
            return antaios_static_symbols[index].address;
        }
    }
    antaios_static_dlerror = "symbol is absent from the static Antaios runtime";
    return NULL;
}

int dlclose(void *handle)
{
    (void)handle;
    antaios_static_dlerror = NULL;
    return 0;
}

char *dlerror(void)
{
    const char *message = antaios_static_dlerror;

    antaios_static_dlerror = NULL;
    return (char *)message;
}
