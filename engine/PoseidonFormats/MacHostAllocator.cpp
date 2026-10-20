// This dylib runs inside Blender, alongside the system libc++. Its C++
// allocations must use the same malloc zone as libc++ (e.g. string growth).
// Defining these here also prevents the static engine's GlobalOperators.o
// from being pulled into the plugin. Engine-specific allocators are unchanged.
#include <cstdlib>
#include <new>

void* operator new(std::size_t size)
{
    for (;;)
    {
        if (void* memory = std::malloc(size ? size : 1))
            return memory;
        if (std::new_handler handler = std::get_new_handler())
            handler();
        else
            throw std::bad_alloc();
    }
}

void* operator new[](std::size_t size)
{
    return ::operator new(size);
}
void operator delete(void* memory) noexcept
{
    std::free(memory);
}
void operator delete[](void* memory) noexcept
{
    std::free(memory);
}
void operator delete(void* memory, std::size_t) noexcept
{
    std::free(memory);
}
void operator delete[](void* memory, std::size_t) noexcept
{
    std::free(memory);
}
