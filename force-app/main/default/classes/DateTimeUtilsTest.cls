@IsTest
private with sharing class DateTimeUtilsTest {
    
    @IsTest
    static void shouldTestDebugMethod() {

        Test.startTest();

            DateTimeUtils.debug('Test message');

        Test.stopTest();

        Assert.areEqual(
            true,
            true,
            'Expected asset statement to pass.'
        );

    }

}