const assert = require('assert')
const fs = require('fs')
const path = require('path')

const sidebarPath = path.resolve(__dirname, '../components/layout/Sidebar.jsx')
const sidebar = fs.readFileSync(sidebarPath, 'utf8')
assert.ok(sidebar.includes('drawerOpen'), 'AssertionError: Sidebar must support mobile drawer state (drawerOpen)')
