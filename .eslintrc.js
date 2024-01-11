module.exports = {
    root: true,
    parser: '@typescript-eslint/parser',
    plugins: ['@typescript-eslint', 'prettier', 'mocha-no-only'],
    extends: ['eslint:recommended', 'plugin:@typescript-eslint/recommended'],
    rules: {
      'comma-spacing': ['error', { before: false, after: true }],
      'prettier/prettier': 'error',
      'mocha-no-only/mocha-no-only': ['error'],
      'padding-line-between-statements': 'error',
      'no-shadow': 'off',
      '@typescript-eslint/no-shadow': 'off',
      'no-var': 'error',
      '@typescript-eslint/no-explicit-any': 'off',
    },
  };