# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "canvas-confetti" # @1.9.4
pin "jspdf" # @4.2.1
pin "@babel/runtime/helpers/slicedToArray", to: "@babel--runtime--helpers--slicedToArray.js" # @7.29.2
pin "@babel/runtime/helpers/typeof", to: "@babel--runtime--helpers--typeof.js" # @7.29.2
pin "fast-png" # @6.4.0
pin "fflate" # @0.8.2
pin "iobuffer" # @2.1.0
pin "pako" # @2.1.0
