/*
 * cyg_hooks.c - empty hooks for a -finstrument-functions build of calls.c.
 * In their own file, so the compiler cannot see they are empty and
 * delete the calls.
 */
__attribute__((no_instrument_function))
void __cyg_profile_func_enter(void *fn, void *site)
{
}

__attribute__((no_instrument_function))
void __cyg_profile_func_exit(void *fn, void *site)
{
}
