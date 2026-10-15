# Welcome to MacMD

A **native**, *fast* and ~~heavy~~ light Markdown editor for macOS — with `inline code`, [links](https://github.com/rodanr/macmd) and a calm reading mode.

> Simplicity is the ultimate sophistication.
> — Leonardo da Vinci

## Lists

- Write in plain Markdown
- See it styled as you type
  - Nested items work too
- [x] Dark & light mode
- [ ] Your next great idea

1. Open a file
2. Press **⌘E** to read
3. Press it again to edit

## Code

```swift
struct Greeting {
    let name: String
    func render() -> String { "Hello, \(name)!" }
}
```

```python
def fib(n: int) -> int:
    return n if n < 2 else fib(n - 1) + fib(n - 2)
```

## Tables

| Feature        | Edit mode | Read mode |
|:---------------|:---------:|----------:|
| Live styling   |     ✓     |     —     |
| Math & diagrams|     —     |     ✓     |
| Outline        |     ✓     |     ✓     |

## Math

Euler's identity $e^{i\pi} + 1 = 0$ is a classic, and so is the Gaussian integral:

$$
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
$$

## Diagrams

```mermaid
graph LR
  A[Write] --> B{Happy?}
  B -- yes --> C[Ship it]
  B -- no --> A
```

---

Made with care · 日本語もOK · emoji 🎉
