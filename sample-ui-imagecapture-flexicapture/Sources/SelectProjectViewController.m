/// ABBYY® Mobile Capture © 2019 ABBYY Production LLC.
/// ABBYY is a registered trademark or a trademark of ABBYY Software Ltd.

#import "SelectProjectViewController.h"

@interface SelectProjectViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, weak) IBOutlet UITableView* tableView;

@end

@implementation SelectProjectViewController

- (void)viewDidLoad
{
	[super viewDidLoad];

	self.tableView.delegate = self;
	self.tableView.dataSource = self;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
	[self.delegate selectedProject:self.projectsNames[indexPath.row]];
	[self.navigationController popViewControllerAnimated:YES];
}

- (nonnull UITableViewCell*)tableView:(nonnull UITableView*)tableView cellForRowAtIndexPath:(nonnull NSIndexPath*)indexPath
{
	UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ProjectCellId"];
	cell.textLabel.text = self.projectsNames[indexPath.row];

	if([self.selectedProjectName isEqualToString:self.projectsNames[indexPath.row]]) {
		cell.accessoryType = UITableViewCellAccessoryCheckmark;
	}

	return cell;
}

- (NSInteger)tableView:(nonnull UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
	return self.projectsNames.count;
}

@end

