import '../entities/contributor.dart';

abstract class ContributorRepository {
  Future<Contributor> createContributor(Contributor contributor);
  Future<Contributor?> getContributor(String id);
  Future<Contributor> updateContributor(Contributor contributor);
}
