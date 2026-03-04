import { createRouter, createWebHistory } from 'vue-router'
import Dashboard from '../views/Dashboard.vue'
import Strategies from '../views/Strategies.vue'
import Signals from '../views/Signals.vue'

const routes = [
  {
    path: '/',
    name: 'Dashboard',
    component: Dashboard
  },
  {
    path: '/strategies',
    name: 'Strategies',
    component: Strategies
  },
  {
    path: '/signals',
    name: 'Signals',
    component: Signals
  }
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

export default router
