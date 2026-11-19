// test only: gives this child process its own computer name, so it is a different device from the others
require('os').hostname = () => process.env.TEST_HOSTNAME || 'test-host';
