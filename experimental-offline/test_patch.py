import hashlib
import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('patch_dll', HERE / 'patch_dll.py')
patch_dll = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch_dll)

try:
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32
    from unicorn.x86_const import UC_X86_REG_EIP, UC_X86_REG_ESI, UC_X86_REG_EBP
except ImportError:
    Uc = None


class PatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = (HERE.parent / 'Application.dll').read_bytes()
        cls.patched = patch_dll.patch(cls.original)

    def test_exact_original_required(self):
        self.assertEqual(hashlib.sha256(self.original).hexdigest(), patch_dll.EXPECTED_SHA256)
        with self.assertRaises(ValueError):
            patch_dll.patch(self.original + b'\0')

    def test_only_unpacker_modified(self):
        self.assertEqual(len(self.original), len(self.patched))
        allowed = set(range(patch_dll.offset(patch_dll.HOOK), patch_dll.offset(patch_dll.HOOK) + 6))
        allowed.update(range(patch_dll.offset(patch_dll.CAVE), patch_dll.offset(patch_dll.CAVE_END)))
        changes = {i for i, (a, b) in enumerate(zip(self.original, self.patched)) if a != b}
        self.assertTrue(changes)
        self.assertLessEqual(changes, allowed)
        self.assertEqual(self.patched, (HERE / 'Application.dll').read_bytes())

    @unittest.skipIf(Uc is None, 'optional unicorn package is not installed')
    def test_trampoline_only_in_emulator(self):
        # Emulate only our short trampoline, not the original program or any OS API.
        for image_base in (0x400000, 0x500000):
            delta = image_base - 0x400000
            u = Uc(UC_ARCH_X86, UC_MODE_32)
            u.mem_map(image_base, 0xb0000)
            start = patch_dll.offset(patch_dll.HOOK)
            end = patch_dll.offset(patch_dll.CAVE_END)
            u.mem_write(patch_dll.HOOK + delta, self.patched[start:end])
            for address, original in ((0x466eac, b'\x55\x8b\xec\x51'),
                                      (0x466f04, b'\x55\x8b\xec\x83'),
                                      (0x46a604, b'\x55\x8b\xec\x33')):
                u.mem_write(address + delta, original)
            u.mem_write(0x4af46c + delta, b'\x78\x56\x34\x12')
            u.reg_write(UC_X86_REG_ESI, 0x401000 + delta)
            u.emu_start(patch_dll.HOOK + delta, 0x4a959d + delta, count=20)
            self.assertEqual(u.reg_read(UC_X86_REG_EIP), 0x4a959d + delta)
            self.assertEqual(u.reg_read(UC_X86_REG_EBP), 0x12345678)
            self.assertEqual(bytes(u.mem_read(0x466eac + delta, 1)), b'\xc3')
            self.assertEqual(bytes(u.mem_read(0x466f04 + delta, 4)), b'\xc2\x04\x00\x00')
            self.assertEqual(bytes(u.mem_read(0x46a604 + delta, 1)), b'\xc3')


if __name__ == '__main__':
    unittest.main()
