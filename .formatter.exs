# Used by "mix format"
locals_without_parens = [
  box: 1,
  box: 2,
  input: 1,
  select: 1,
  text: 1,
  text: 2
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test,examples}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
