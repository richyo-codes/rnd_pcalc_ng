[] {
    auto factorial = [](auto&& self, unsigned n)
        constexpr -> unsigned long long {
        return n <= 1 ? 1 : n * self(self, n - 1);
    };

    return factorial(factorial, 10);
}()
