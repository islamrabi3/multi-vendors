/// Rows fetched per page by the paged admin/vendor lists.
///
/// One constant so the repository `.range()` window, the "no more results"
/// check (`page.length == kPageSize`) and the scroll trigger always agree.
const kPageSize = 25;
