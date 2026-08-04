import { createRoot, createSignal, untrack } from 'solid-js';
import { ActionType } from '../types';
import { defaultToasterOptions, defaultToastOptions, defaultTimeouts } from './defaults';
import { generateID } from '../util';
import { dispatch, store } from './store';
import { resolveValue } from '../types';
export const [defaultOpts, setDefaultOpts] = createSignal(defaultToasterOptions);
export const createToast = (message, type = 'blank', options) => ({
    ...defaultToastOptions,
    ...defaultOpts().toastOptions,
    ...options,
    type,
    message,
    pauseDuration: 0,
    createdAt: Date.now(),
    visible: true,
    id: options.id || generateID(),
    paused: false,
    style: {
        ...defaultToastOptions.style,
        ...defaultOpts().toastOptions?.style,
        ...options.style,
    },
    duration: options.duration || defaultOpts().toastOptions?.duration || defaultTimeouts[type],
    position: options.position || defaultOpts().toastOptions?.position || defaultOpts().position || defaultToastOptions.position,
});
const createToastCreator = (type) => (message, options = {}) => {
    return createRoot(() => {
        const existingToast = store.toasts.find((t) => t.id === options.id);
        const toast = createToast(message, type, { ...existingToast, duration: undefined, ...options });
        dispatch({ type: ActionType.UPSERT_TOAST, toast });
        return toast.id;
    });
};
const toast = (message, opts) => createToastCreator('blank')(message, opts);
const test = untrack(() => toast);
toast.error = createToastCreator('error');
toast.success = createToastCreator('success');
toast.loading = createToastCreator('loading');
toast.custom = createToastCreator('custom');
toast.dismiss = (toastId) => {
    dispatch({
        type: ActionType.DISMISS_TOAST,
        toastId,
    });
};
toast.promise = (promise, msgs, opts) => {
    const id = toast.loading(msgs.loading, { ...opts });
    promise
        .then((p) => {
        toast.success(resolveValue(msgs.success, p), {
            id,
            ...opts,
        });
        return p;
    })
        .catch((e) => {
        toast.error(resolveValue(msgs.error, e), {
            id,
            ...opts,
        });
    });
    return promise;
};
toast.remove = (toastId) => {
    dispatch({
        type: ActionType.REMOVE_TOAST,
        toastId,
    });
};
export { toast };
