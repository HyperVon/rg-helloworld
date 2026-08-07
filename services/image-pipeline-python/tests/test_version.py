import unittest

from rg_image_pipeline import SERVICE_NAME, __version__, banner


class VersionTest(unittest.TestCase):
    def test_version_is_not_empty(self) -> None:
        self.assertTrue(__version__)

    def test_version_matches_milestone7(self) -> None:
        self.assertEqual(__version__, "0.1.0-milestone11")

    def test_service_name_is_set(self) -> None:
        self.assertEqual(SERVICE_NAME, "image-pipeline")

    def test_banner_includes_service_and_version(self) -> None:
        self.assertEqual(banner(), "image-pipeline 0.1.0-milestone11")


if __name__ == "__main__":
    unittest.main()
