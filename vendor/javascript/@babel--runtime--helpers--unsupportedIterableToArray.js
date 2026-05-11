// @babel/runtime/helpers/unsupportedIterableToArray@7.29.2 downloaded from https://ga.jspm.io/npm:@babel/runtime@7.29.2/helpers/esm/unsupportedIterableToArray.js

import e from"./arrayLikeToArray.js";function t(t,n){if(t){if(typeof t==`string`)return e(t,n);var r={}.toString.call(t).slice(8,-1);return r===`Object`&&t.constructor&&(r=t.constructor.name),r===`Map`||r===`Set`?Array.from(t):r===`Arguments`||/^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(r)?e(t,n):void 0}}export{t as default};

