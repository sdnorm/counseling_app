json.name brand.name
json.short_name brand.name
json.start_url "/"
json.display "standalone"
json.background_color "#f3f8f9"
json.theme_color brand.primary_color
json.icons [ 192, 512 ] do |size|
  variant = brand.icon_variant(size)
  json.src variant ? url_for(variant) : image_path("generic/icon-#{size}.png")
  json.sizes "#{size}x#{size}"
  json.type "image/png"
end
