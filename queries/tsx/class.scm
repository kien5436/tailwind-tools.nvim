(jsx_attribute
  (property_identifier) @_attribute_name
  (#any-of? @_attribute_name "class" "className" "tw")
  [
    (string
      (string_fragment) @tailwind)
    (jsx_expression
      (template_string) @tailwind.inner)
  ])
