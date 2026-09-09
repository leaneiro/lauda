# Demonstração de código

Vários blocos coloridos e, no final, um bloco longo que atravessa páginas.

## Swift

```swift
// Saudação simples
struct Saudacao {
    let nome: String
    func dizerOi() -> String {
        "Olá, \(nome)! Você tem \(42) mensagens."
    }
}
```

## Python

```python
# fibonacci memoizado
def fib(n, memo={0: 0, 1: 1}):
    if n not in memo:
        memo[n] = fib(n - 1) + fib(n - 2)
    return memo[n]
```

## JavaScript

```js
/* debounce clássico */
const debounce = (fn, ms = 150) => {
  let id = null;
  return (...args) => {
    clearTimeout(id);
    id = setTimeout(() => fn(...args), ms);
  };
};
```

## SQL

```sql
SELECT autor, COUNT(*) AS posts
FROM artigos
WHERE publicado = 'sim' -- só publicados
GROUP BY autor ORDER BY posts DESC LIMIT 10;
```

## JSON

```json
{ "nome": "MarkEditor", "versao": 1.0, "nativo": true, "deps": null }
```

## Bloco longo

```swift
// inicio do bloco longo
let valor1 = calcular(indice: 1) // linha 1
let valor2 = calcular(indice: 2) // linha 2
let valor3 = calcular(indice: 3) // linha 3
let valor4 = calcular(indice: 4) // linha 4
let valor5 = calcular(indice: 5) // linha 5
let valor6 = calcular(indice: 6) // linha 6
let valor7 = calcular(indice: 7) // linha 7
let valor8 = calcular(indice: 8) // linha 8
let valor9 = calcular(indice: 9) // linha 9
let valor10 = calcular(indice: 10) // linha 10
let valor11 = calcular(indice: 11) // linha 11
let valor12 = calcular(indice: 12) // linha 12
let valor13 = calcular(indice: 13) // linha 13
let valor14 = calcular(indice: 14) // linha 14
let valor15 = calcular(indice: 15) // linha 15
let valor16 = calcular(indice: 16) // linha 16
let valor17 = calcular(indice: 17) // linha 17
let valor18 = calcular(indice: 18) // linha 18
let valor19 = calcular(indice: 19) // linha 19
let valor20 = calcular(indice: 20) // linha 20
let valor21 = calcular(indice: 21) // linha 21
let valor22 = calcular(indice: 22) // linha 22
let valor23 = calcular(indice: 23) // linha 23
let valor24 = calcular(indice: 24) // linha 24
let valor25 = calcular(indice: 25) // linha 25
let valor26 = calcular(indice: 26) // linha 26
let valor27 = calcular(indice: 27) // linha 27
let valor28 = calcular(indice: 28) // linha 28
let valor29 = calcular(indice: 29) // linha 29
let valor30 = calcular(indice: 30) // linha 30
let valor31 = calcular(indice: 31) // linha 31
let valor32 = calcular(indice: 32) // linha 32
let valor33 = calcular(indice: 33) // linha 33
let valor34 = calcular(indice: 34) // linha 34
let valor35 = calcular(indice: 35) // linha 35
let valor36 = calcular(indice: 36) // linha 36
let valor37 = calcular(indice: 37) // linha 37
let valor38 = calcular(indice: 38) // linha 38
let valor39 = calcular(indice: 39) // linha 39
let valor40 = calcular(indice: 40) // linha 40
let valor41 = calcular(indice: 41) // linha 41
let valor42 = calcular(indice: 42) // linha 42
let valor43 = calcular(indice: 43) // linha 43
let valor44 = calcular(indice: 44) // linha 44
let valor45 = calcular(indice: 45) // linha 45
let valor46 = calcular(indice: 46) // linha 46
let valor47 = calcular(indice: 47) // linha 47
let valor48 = calcular(indice: 48) // linha 48
let valor49 = calcular(indice: 49) // linha 49
let valor50 = calcular(indice: 50) // linha 50
let valor51 = calcular(indice: 51) // linha 51
let valor52 = calcular(indice: 52) // linha 52
let valor53 = calcular(indice: 53) // linha 53
let valor54 = calcular(indice: 54) // linha 54
let valor55 = calcular(indice: 55) // linha 55
let valor56 = calcular(indice: 56) // linha 56
let valor57 = calcular(indice: 57) // linha 57
let valor58 = calcular(indice: 58) // linha 58
let valor59 = calcular(indice: 59) // linha 59
let valor60 = calcular(indice: 60) // linha 60
// fim do bloco longo
```
