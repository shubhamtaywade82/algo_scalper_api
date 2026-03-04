import { createConsumer } from '@rails/actioncable'

// /cable is proxied to ws://localhost:3000/cable by Vite dev server
export default createConsumer('/cable')
