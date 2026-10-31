'use strict';
const host = () => globalThis.AndroidHost;
module.exports = {
  homedir: () => host().home(),
  tmpdir: () => host().tmp(),
  platform: () => 'android',
  EOL: '\n',
};
