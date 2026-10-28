const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('container/web/clipboard-helper.js', 'utf8');

function setup({ value = 'Grüße 👋', writeText, legacyCopy = false } = {}) {
    const nodes = new Map();
    function element() {
        return {
            children: [], handlers: {}, textContent: '',
            append(...children) { this.children.push(...children); },
            setAttribute() {},
            addEventListener(event, handler) { this.handlers[event] = handler; },
            focus() { this.focused = true; },
            select() { this.selected = true; },
            insertAdjacentElement(position, sibling) { this.controls = sibling; },
        };
    }
    const field = element();
    field.value = value;
    nodes.set('noVNC_clipboard_text', field);
    const document = {
        readyState: 'complete',
        getElementById: id => nodes.get(id),
        createElement() {
            const node = element();
            Object.defineProperty(node, 'id', { set(id) { nodes.set(id, node); } });
            return node;
        },
        execCommand(command) { assert.equal(command, 'copy'); return legacyCopy; },
    };
    vm.runInNewContext(source, { document, navigator: { clipboard: { writeText } } });
    return {
        field,
        click: () => nodes.get('remote_clipboard_copy').handlers.click(),
        status: () => field.controls.children[2].textContent,
    };
}

test('copies Unicode text only after the user clicks', async () => {
    const writes = [];
    const page = setup({ writeText: async text => writes.push(text) });
    assert.equal(writes.length, 0);
    await page.click();
    assert.deepEqual(writes, ['Grüße 👋']);
    assert.match(page.status(), /^Kopiert/);
});

test('permission refusal selects the text and explains manual copying', async () => {
    const page = setup({ writeText: async () => { throw Error('denied'); } });
    await page.click();
    assert.equal(page.field.focused, true);
    assert.equal(page.field.selected, true);
    assert.match(page.status(), /⌘C/);
});

test('missing Clipboard API can use the legacy copy path', async () => {
    const page = setup({ legacyCopy: true });
    await page.click();
    assert.match(page.status(), /^Kopiert/);
});

test('empty remote clipboard does not erase the local clipboard', async () => {
    const page = setup({ value: '', writeText: () => { throw Error('must not run'); } });
    await page.click();
    assert.match(page.status(), /Noch kein Text/);
});
